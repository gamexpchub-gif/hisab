"""
Hisab AI — the language brain on your server (Claude by Anthropic).

The app sends what the person typed or said, plus the shop's product list
and customers (names, prices, stock — only what the person may see). Claude
understands it in any language or mix (Bangla, Banglish, English, Hindi) and
answers with ACTIONS the app shows as cards to confirm:

    create_bill · receive_payment · add_customer · add_expense · ask_books

Nothing is saved here: the app saves only what the person confirms, in its
own books. The API key stays on the server (/etc/hisab-sync.env), never in
the app.
"""
import json
import os
import threading
import time

try:
    import anthropic
except ImportError:  # the server still runs the live sync without the AI
    anthropic = None

MODEL = os.environ.get('HISAB_AI_MODEL', 'claude-opus-5-5')
MAX_PER_HOUR = int(os.environ.get('HISAB_AI_PER_HOUR', '120'))  # per account

_client = None
_lock = threading.Lock()
_calls = {}  # uid -> [timestamps]

SYSTEM = """You are Hisab AI, the assistant inside an accounting and billing app for small Indian shops (mobiles, PCs, accessories).
The person using the app is the shop owner or a staff member. They write or speak in Bangla, Banglish (Bangla in Latin letters), English or Hindi, often mixed and with spelling mistakes. Numbers like "18 hajar" = 18000, "dera lakh" = 150000, "ekta/duita" = 1/2, "baki/udhar" = on credit, "joma" = money received, "khoroch" = expense.

Act through the tools. Rules:
- A sale ("ke ... becho", "bill koro", "dilam", a product with a price) → create_bill. Use product_id values ONLY from the PRODUCTS list; pick the closest name/variant. unit_price is what the customer pays per unit in rupees including GST; null when no price was said (the list price is used).
- The customer: use customer_id from the CUSTOMERS list when the name or mobile matches; otherwise give the new customer's name and/or mobile. A walk-in sale has no customer.
- payment: cash, upi, card or credit. "baki" / "udhar" / part payment → credit, with advance = the amount paid now.
- Money a customer pays against dues → receive_payment. A new customer without a sale → add_customer. A shop cost (rent, salary, electricity, tea, transport…) → add_expense.
- Any question about the shop's numbers (sales, profit, dues, stock, a customer's khata, prices, bills, low stock, best sellers, a period or a brand) → ask_books with ONE clear English question for the shop's own report engine, e.g. "profit last month on Vivo", "Rahim Sheikh khata", "low stock", "sales today", "price of Vivo T3". Do not invent numbers.
- Several actions in one message are fine (e.g. two bills, or a bill and an expense).
- Only use actions the person is allowed to do (ALLOWED list). If they ask for something not allowed, say politely that it needs the owner's permission.
- If a product is not in the list, say so briefly and suggest the closest ones.
- After the tools, write one short line in the person's own language and style (Banglish if they wrote Banglish) saying what you prepared. No long explanations, no markdown tables."""

_bill_item = {
    "type": "object",
    "properties": {
        "product_id": {"type": "integer"},
        "qty": {"type": "integer"},
        "unit_price": {"type": ["number", "null"], "description": "Rupees per unit incl. GST, or null for the list price"},
    },
    "required": ["product_id", "qty", "unit_price"],
    "additionalProperties": False,
}

_customer = {
    "customer_id": {"type": ["integer", "null"], "description": "From CUSTOMERS, or null"},
    "new_customer_name": {"type": ["string", "null"]},
    "new_customer_phone": {"type": ["string", "null"], "description": "10-digit Indian mobile, or null"},
}

TOOLS = [
    {
        "name": "create_bill",
        "description": "Prepare a sale bill for the person to check and save.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {
                **_customer,
                "items": {"type": "array", "items": _bill_item},
                "payment": {"type": "string", "enum": ["cash", "upi", "card", "credit"]},
                "advance": {"type": ["number", "null"], "description": "Rupees paid now on a credit bill, or null"},
            },
            "required": ["customer_id", "new_customer_name", "new_customer_phone", "items", "payment", "advance"],
            "additionalProperties": False,
        },
    },
    {
        "name": "receive_payment",
        "description": "Money received from a customer against their dues.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {
                "customer_id": {"type": ["integer", "null"]},
                "customer_name": {"type": ["string", "null"], "description": "As said, when not in CUSTOMERS"},
                "amount": {"type": "number", "description": "Rupees"},
                "method": {"type": "string", "enum": ["cash", "upi", "card"]},
            },
            "required": ["customer_id", "customer_name", "amount", "method"],
            "additionalProperties": False,
        },
    },
    {
        "name": "add_customer",
        "description": "Save a new customer.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "phone": {"type": "string"}},
            "required": ["name", "phone"],
            "additionalProperties": False,
        },
    },
    {
        "name": "add_expense",
        "description": "Record a shop expense.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {
                "category": {"type": "string", "description": "Rent, Electricity, Salary, Tea & snacks, Transport, Internet & phone, Repairs & maintenance, Stationery, or a short new name"},
                "amount": {"type": "number", "description": "Rupees"},
                "method": {"type": "string", "enum": ["cash", "upi", "card"]},
                "note": {"type": "string"},
            },
            "required": ["category", "amount", "method", "note"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ask_books",
        "description": "Ask the shop's own report engine a question about its numbers; the app shows the answer.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {"question": {"type": "string", "description": "One clear English question"}},
            "required": ["question"],
            "additionalProperties": False,
        },
    },
]


def available():
    return anthropic is not None and bool(os.environ.get('ANTHROPIC_API_KEY'))


def _get_client():
    global _client
    with _lock:
        if _client is None:
            _client = anthropic.Anthropic(timeout=45.0, max_retries=2)
        return _client


def _allow(uid):
    now = time.time()
    with _lock:
        recent = [t for t in _calls.get(uid, []) if now - t < 3600]
        if len(recent) >= MAX_PER_HOUR:
            _calls[uid] = recent
            return False
        recent.append(now)
        _calls[uid] = recent
        return True


def _catalog(req):
    """The shop's data for this request, as compact text (it changes rarely,
    so it sits in a cached system block after the fixed instructions)."""
    prods = req.get('products') or []
    custs = req.get('customers') or []
    lines = [f"SHOP: {req.get('shop') or 'Shop'} · today {req.get('today') or ''}",
             f"ALLOWED: {', '.join(req.get('allowed') or [])}",
             "PRODUCTS (id | name | variant | price incl. GST ₹ | stock):"]
    for p in prods[:600]:
        lines.append(f"{p.get('id')} | {p.get('name')} | {p.get('variant') or ''} | {p.get('price')} | {p.get('stock')}")
    lines.append("CUSTOMERS (id | name | mobile):")
    for c in custs[:800]:
        lines.append(f"{c.get('id')} | {c.get('name')} | {c.get('phone') or ''}")
    return '\n'.join(lines)


def handle(uid, req):
    """Returns (http_status, body_dict)."""
    if not available():
        return 503, {'error': 'AI is not set up on the server (no API key)'}
    if not _allow(uid):
        return 429, {'error': 'Too many AI requests this hour — try again a little later'}
    text = str(req.get('message') or '').strip()
    if not text or len(text) > 2000:
        return 400, {'error': 'Say or type a request (up to 2000 letters)'}
    history = []
    for h in (req.get('history') or [])[-6:]:
        role = 'assistant' if h.get('role') == 'assistant' else 'user'
        t = str(h.get('text') or '').strip()[:1500]
        if t:
            history.append({'role': role, 'content': t})
    # the conversation must start with the person and alternate
    msgs = []
    for m in history + [{'role': 'user', 'content': text}]:
        if msgs and msgs[-1]['role'] == m['role']:
            msgs[-1]['content'] += '\n' + m['content']
        else:
            msgs.append(dict(m))
    while msgs and msgs[0]['role'] != 'user':
        msgs.pop(0)

    try:
        resp = _get_client().beta.messages.create(
            model=MODEL,
            max_tokens=4000,
            output_config={'effort': 'low'},  # quick answers; the task is short
            betas=['server-side-fallback-2026-07-01'],
            fallbacks='default',  # a declined request is re-run on a fallback model
            system=[
                {'type': 'text', 'text': SYSTEM},
                {'type': 'text', 'text': _catalog(req), 'cache_control': {'type': 'ephemeral'}},
            ],
            tools=TOOLS,
            messages=msgs,
        )
    except anthropic.RateLimitError:
        return 429, {'error': 'The AI is busy — try again in a moment'}
    except anthropic.APIStatusError as e:
        return 502, {'error': f'AI error {e.status_code}'}
    except anthropic.APIConnectionError:
        return 502, {'error': 'The server could not reach the AI'}

    if resp.stop_reason == 'refusal':
        return 200, {'text': 'Sorry, I can\'t help with that.', 'actions': []}
    actions, texts = [], []
    for b in resp.content:
        if b.type == 'tool_use':
            # inputs are parsed JSON (never string-matched)
            actions.append({'tool': b.name, 'input': b.input})
        elif b.type == 'text' and b.text.strip():
            texts.append(b.text.strip())
    return 200, {'text': '\n'.join(texts), 'actions': actions, 'model': resp.model}


if __name__ == '__main__':
    print(json.dumps({'available': available(), 'model': MODEL}))
