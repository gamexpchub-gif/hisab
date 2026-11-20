#!/usr/bin/env python3
"""
Hisab AI — live sync server (runs on your VPS behind nginx).

The app sends every change of the books here within seconds:
  · the database in pieces (each piece stored once by its hash, gzip'd)
  · a small manifest per store saying which pieces make the newest copy
Photos stay in Firebase. Only the signed-in owner can read or write their
own data: every request carries the Firebase ID token, which is checked
with Google (Identity Toolkit accounts:lookup) and cached until it expires.

Storage:  /var/lib/hisab-sync/<uid>/blobs/<key>
          /var/lib/hisab-sync/<uid>/manifests/<store>_<slot>.json
API (all under /hisab/api/, JSON unless noted):
  GET    health                         → {"ok": true}
  HEAD   blob/<key>                     → 200 if stored
  PUT    blob/<key>        (gzip bytes) → {"ok": true}
  GET    blob/<key>                     → gzip bytes
  DELETE blob/<key>
  PUT    manifest/<store>/<slot> (JSON) → {"ok": true}
  GET    manifests                      → [{"store","slot","created",...}]
  GET    manifest/<store>/<slot>        → the manifest JSON
  GET    wait/<store>?after=<created>   → waits (up to 25 s) until a copy newer
                                          than <created> arrives; returns the
                                          newest {"created","slot","device"}
                                          — phones use it to see each other's
                                          changes at once
Standard library only (Python 3.8+). No database, no pip.
"""
import hashlib
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

API_KEY = os.environ.get('HISAB_API_KEY', 'AIzaSyAk1N6Aw3BJk50Tsw2Z_KPDfQzJlC-5GIU')
DATA = os.environ.get('HISAB_DATA', '/var/lib/hisab-sync')
PORT = int(os.environ.get('HISAB_PORT', '8787'))
MAX_BODY = 8 * 1024 * 1024          # one piece / manifest
MAX_USER_BYTES = 3 * 1024 ** 3      # 3 GB per account
TEST_TOKEN = os.environ.get('HISAB_TEST_TOKEN')  # local tests only: "token:uid"

KEY_RE = re.compile(r'^[A-Za-z0-9_\-]{8,120}$')
STORE_RE = re.compile(r'^[A-Za-z0-9_\-]{1,40}$')
SLOT_RE = re.compile(r'^[ab]$')

_tokens = {}   # sha256(token) -> (uid, expires)
_lock = threading.Lock()
_changed = threading.Condition()   # notified on every new manifest


def uid_for(token):
    """The Firebase user of an ID token, or None."""
    if not token:
        return None
    if TEST_TOKEN and ':' in TEST_TOKEN:
        t, u = TEST_TOKEN.split(':', 1)
        return u if token == t else None
    h = hashlib.sha256(token.encode()).hexdigest()
    now = time.time()
    with _lock:
        hit = _tokens.get(h)
        if hit and hit[1] > now:
            return hit[0]
    try:
        req = urllib.request.Request(
            f'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={API_KEY}',
            data=json.dumps({'idToken': token}).encode(),
            headers={'Content-Type': 'application/json'}, method='POST')
        with urllib.request.urlopen(req, timeout=10) as r:
            users = json.load(r).get('users') or []
        if not users:
            return None
        uid = users[0]['localId']
    except (urllib.error.URLError, ValueError, KeyError):
        return None
    with _lock:
        if len(_tokens) > 5000:
            _tokens.clear()
        _tokens[h] = (uid, now + 50 * 60)   # ID tokens live 60 min
    return uid


def user_dir(uid, *parts):
    if not re.match(r'^[A-Za-z0-9]{6,128}$', uid):
        raise ValueError('bad uid')
    return os.path.join(DATA, uid, *parts)


def used_bytes(uid):
    total = 0
    for root, _, files in os.walk(user_dir(uid)):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def newest(uid, store):
    """The newest manifest of a store: (created, slot, device) or None."""
    best = None
    for slot in ('a', 'b'):
        path = user_dir(uid, 'manifests', f'{store}_{slot}.json')
        try:
            with open(path) as f:
                m = json.load(f)
        except (OSError, ValueError):
            continue
        c = str(m.get('created') or '')
        if best is None or c > best[0]:
            best = (c, slot, m.get('install') or m.get('device') or '')
    return best


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f'{path}.{os.getpid()}.{threading.get_ident()}.tmp'
    with open(tmp, 'wb') as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


class Handler(BaseHTTPRequestHandler):
    server_version = 'HisabSync/1.0'
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):  # quiet: nginx keeps the access log
        pass

    # ------------------------------------------------------------ helpers
    def send(self, code, body=b'', ctype='application/json'):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def path_parts(self):
        p = self.path.split('?', 1)[0]
        p = re.sub(r'^/+(hisab/api/)?', '', p)
        return [x for x in p.split('/') if x]

    def auth(self):
        h = self.headers.get('Authorization', '')
        uid = uid_for(h[7:] if h.startswith('Bearer ') else None)
        if not uid:
            self.send(401, {'error': 'Sign in again (token not valid)'})
        return uid

    def body(self):
        n = int(self.headers.get('Content-Length') or 0)
        if n > MAX_BODY:
            raise ValueError('too large')
        return self.rfile.read(n) if n else b''

    # ------------------------------------------------------------ routes
    def do_GET(self):
        parts = self.path_parts()
        if parts == ['health']:
            return self.send(200, {'ok': True, 'time': int(time.time())})
        uid = self.auth()
        if not uid:
            return
        try:
            if len(parts) == 2 and parts[0] == 'blob' and KEY_RE.match(parts[1]):
                path = user_dir(uid, 'blobs', parts[1])
                if not os.path.exists(path):
                    return self.send(404, {'error': 'not found'})
                with open(path, 'rb') as f:
                    return self.send(200, f.read(), 'application/octet-stream')
            if parts == ['manifests']:
                out = []
                d = user_dir(uid, 'manifests')
                if os.path.isdir(d):
                    for name in sorted(os.listdir(d)):
                        if not name.endswith('.json'):
                            continue
                        try:
                            with open(os.path.join(d, name)) as f:
                                m = json.load(f)
                            out.append({k: m.get(k) for k in ('store', 'storeName', 'slot', 'created', 'sales', 'products', 'customers', 'bytes', 'device')})
                        except (OSError, ValueError):
                            pass
                return self.send(200, out)
            if len(parts) == 3 and parts[0] == 'manifest' and STORE_RE.match(parts[1]) and SLOT_RE.match(parts[2]):
                path = user_dir(uid, 'manifests', f'{parts[1]}_{parts[2]}.json')
                if not os.path.exists(path):
                    return self.send(404, {'error': 'not found'})
                with open(path, 'rb') as f:
                    return self.send(200, f.read())
            if len(parts) == 2 and parts[0] == 'wait' and STORE_RE.match(parts[1]):
                after, hold = '', 25.0
                if '?' in self.path:
                    from urllib.parse import parse_qs
                    q = parse_qs(self.path.split('?', 1)[1])
                    after = (q.get('after') or [''])[0]
                    try:
                        hold = max(0.0, min(25.0, float((q.get('hold') or ['25'])[0])))
                    except ValueError:
                        pass
                deadline = time.time() + hold
                n = newest(uid, parts[1])
                with _changed:
                    while (n is None or n[0] <= after) and time.time() < deadline:
                        _changed.wait(timeout=max(0.1, deadline - time.time()))
                        n = newest(uid, parts[1])
                if n is None:
                    return self.send(200, {'created': None})
                return self.send(200, {'created': n[0], 'slot': n[1], 'install': n[2], 'changed': n[0] > after})
            if parts == ['usage']:
                return self.send(200, {'bytes': used_bytes(uid), 'limit': MAX_USER_BYTES})
        except ValueError as e:
            return self.send(400, {'error': str(e)})
        self.send(404, {'error': 'unknown'})

    def do_HEAD(self):
        parts = self.path_parts()
        uid = self.auth()
        if not uid:
            return
        if len(parts) == 2 and parts[0] == 'blob' and KEY_RE.match(parts[1]):
            return self.send(200 if os.path.exists(user_dir(uid, 'blobs', parts[1])) else 404)
        self.send(404)

    def do_PUT(self):
        parts = self.path_parts()
        uid = self.auth()
        if not uid:
            return
        try:
            data = self.body()
            if len(parts) == 2 and parts[0] == 'blob' and KEY_RE.match(parts[1]):
                if used_bytes(uid) + len(data) > MAX_USER_BYTES:
                    return self.send(507, {'error': 'Storage full for this account'})
                write_atomic(user_dir(uid, 'blobs', parts[1]), data)
                return self.send(200, {'ok': True})
            if len(parts) == 3 and parts[0] == 'manifest' and STORE_RE.match(parts[1]) and SLOT_RE.match(parts[2]):
                m = json.loads(data.decode())
                if not isinstance(m, dict) or 'db' not in m:
                    return self.send(400, {'error': 'bad manifest'})
                # every database piece must be here before the manifest names it
                missing = [k for k in m['db'].get('keys', []) if not KEY_RE.match(k) or not os.path.exists(user_dir(uid, 'blobs', k))]
                if missing:
                    return self.send(409, {'error': 'pieces missing', 'missing': missing[:20]})
                m['store'], m['slot'], m['received'] = parts[1], parts[2], int(time.time())
                write_atomic(user_dir(uid, 'manifests', f'{parts[1]}_{parts[2]}.json'), json.dumps(m).encode())
                with _changed:
                    _changed.notify_all()
                return self.send(200, {'ok': True})
        except (ValueError, UnicodeDecodeError) as e:
            return self.send(400, {'error': str(e)})
        self.send(404, {'error': 'unknown'})

    def do_DELETE(self):
        parts = self.path_parts()
        uid = self.auth()
        if not uid:
            return
        if len(parts) == 2 and parts[0] == 'blob' and KEY_RE.match(parts[1]):
            try:
                os.remove(user_dir(uid, 'blobs', parts[1]))
            except FileNotFoundError:
                pass
            return self.send(200, {'ok': True})
        self.send(404, {'error': 'unknown'})


def main():
    os.makedirs(DATA, exist_ok=True)
    srv = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    srv.daemon_threads = True
    print(f'Hisab sync on 127.0.0.1:{PORT}, data in {DATA}', flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--check':
        print('ok')
        sys.exit(0)
    main()
