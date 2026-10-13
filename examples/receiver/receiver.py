#!/usr/bin/env python3
"""Minimal MacVitals webhook receiver: verifies the HMAC signature and saves each report.

Standard library only. Good for local testing and as a reference for writing your own
receiver (Azure Function, AWS Lambda, n8n code node...).

    MACVITALS_SECRET=change-me python3 receiver.py --port 8787 --out ./received

Put a TLS-terminating proxy in front of it for anything beyond localhost.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 20 * 1024 * 1024
TOLERANCE_SECONDS = 300


def verify(secret: bytes, body: bytes, timestamp: str, signature: str) -> bool:
    """Mirror of RequestSignature.verify in Swift: HMAC-SHA256 over "<timestamp>.<body>"."""
    try:
        if abs(time.time() - int(timestamp)) > TOLERANCE_SECONDS:
            return False
    except (TypeError, ValueError):
        return False
    expected = "sha256=" + hmac.new(secret, f"{timestamp}.".encode() + body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature or "")


def make_handler(secret: bytes | None, out_dir: str):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            if length <= 0 or length > MAX_BODY:
                return self.reply(413, "bad length")
            body = self.rfile.read(length)

            if secret is not None and not verify(secret, body,
                                                 self.headers.get("X-MacVitals-Timestamp"),
                                                 self.headers.get("X-MacVitals-Signature")):
                return self.reply(401, "invalid signature")

            try:
                payload = json.loads(body)
                html = base64.b64decode(payload["contentBase64"], validate=True)
            except (ValueError, KeyError):
                return self.reply(400, "invalid payload")

            # Never trust a client-supplied file name as a path.
            name = re.sub(r"[^A-Za-z0-9._-]", "-", os.path.basename(payload.get("fileName", "report.html")))
            path = os.path.join(out_dir, name)
            with open(path, "wb") as f:
                f.write(html)

            findings = ", ".join(i["title"] for i in payload.get("insights", [])) or "none yet"
            print(f"[{payload['kind']}] {payload['computerName']} -> {path} | findings: {findings}", flush=True)
            self.reply(200, "ok")

        def reply(self, status: int, text: str):
            self.send_response(status)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(text.encode())

        def log_message(self, *args):
            pass

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--out", default="received")
    args = parser.parse_args()

    secret = os.environ.get("MACVITALS_SECRET")
    if not secret:
        print("WARNING: MACVITALS_SECRET not set, signatures are NOT verified")
    os.makedirs(args.out, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(secret.encode() if secret else None, args.out))
    print(f"Listening on http://{args.host}:{args.port}, saving reports to {os.path.abspath(args.out)}")
    server.serve_forever()


if __name__ == "__main__":
    main()
