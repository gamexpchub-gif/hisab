# GameX Hisab — GAMEX PC Hub Accounting App (Android)

Offline-first accounting, billing and inventory app for **GAMEX PC Hub** (mobile & laptop shop).
Built with Flutter; all data is stored on the phone in SQLite, so it works without internet or a server.

## APK download

Every push builds the APK with GitHub Actions (`.github/workflows/build-apk.yml`):

- **Actions** tab → latest *Build APK* run → **Artifacts** → `GameX-Hisab-apk` (zip containing `GameX-Hisab.apk`)
- Pushes to `main` also publish the APK on the **Releases** page.

Install on Android: open the APK → allow "Install unknown apps" for your browser/file manager.

## What works today

| Area | Features |
|---|---|
| Home | GameX header, notifications badge, welcome banner, today's sales / purchases / yesterday / total due cards, 8 quick actions, business overview (today / week / month / year with % change), search, recent activity, floating **New sale** |
| Sales | GST invoice with multiple items, IMEI/serial per line, discount, cash/credit/partial payment, walk-in or customer, copy invoice for WhatsApp, profit per invoice |
| Purchase | Supplier bill, bill no., GST input, partial payment, weighted-average costing |
| Stock | Products, categories, brand, SKU, HSN, GST %, condition (new/used/refurbished), opening stock, low-stock alerts, stock value |
| Parties | Customers & suppliers, opening balance, credit limit, ledger statement, receive / make payment |
| Money | Cash, SBI, UPI + any extra bank/wallet, transfers (contra), account ledgers |
| Expenses | 10 built-in heads + custom categories |
| Accounting | Automatic double-entry for every transaction, chart of accounts, journal with duplicate-post protection |
| Reports | Dashboard (profit today, monthly chart, top products, highest dues), P&L, Balance Sheet, Trial Balance, Day Book, GST summary |

## Accounting rules the engine enforces

1. Every transaction posts one journal entry where **debit = credit**, inside the same DB transaction.
2. A document can never be posted twice (`UNIQUE(source_type, source_id)`).
3. Money is stored as **integer paise** — no floating-point errors.
4. Sales post **COGS at weighted-average cost**, so profit is real profit, not "sales − purchases".
5. Stock can't go below zero; walk-in sales must be fully paid.

## Project layout

```
lib/core/   money.dart (paise maths, ₹ formatting) · db.dart (schema, chart of accounts) · books.dart (accounting engine + reports)
lib/ui/     theme.dart (colours) · art.dart (3D illustrations drawn in code) · widgets.dart (glass cards, tiles, lists)
lib/screens home, dashboard, sales/purchase forms, invoices, products, parties, expenses, bank, ledgers, reports, menu, settings
test/       books_test.dart (double-entry checks) · widget_test.dart
tool/       make_icon.py + generated launcher icons
```

## Local development

```bash
flutter create --platforms=android --org com.gamexpchub --project-name hisab .   # first time only
flutter pub get
flutter test
flutter run
```

See [ROADMAP.md](ROADMAP.md) for the full feature plan.
