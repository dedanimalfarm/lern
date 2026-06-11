#!/usr/bin/env python3
"""Webhook sink — приёмник вебхуков для модуля 06 (интеграции).

Играет роль «внешней системы» (мессенджер/мониторинг/CMDB), которую
Helpdesk API уведомляет о событиях. Принимает POST на любой путь,
складывает доставки в память и отдаёт их списком — чтобы студент
(и verify-скрипт) мог убедиться, что интеграция реально сработала.

Эндпоинты:
  POST /hook      — принять событие (любой JSON)
  GET  /received  — все принятые события, новые в конце
  POST /_reset    — очистить память

Конфигурация: PORT (default 9100).
Запуск: python3 webhook_sink.py
"""

import json
import os
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "9100"))
RECEIVED = []
STARTED_AT = time.time()


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "WebhookSink/1.0"

    def send_json(self, status, obj):
        body = json.dumps(obj, ensure_ascii=False,
                          separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # noqa: N802
        print(f"[{now_iso()}] {self.client_address[0]} {fmt % args}",
              flush=True)

    def do_GET(self):  # noqa: N802
        if self.path == "/received":
            return self.send_json(200, {"count": len(RECEIVED),
                                        "deliveries": RECEIVED})
        if self.path == "/health":
            return self.send_json(200, {"status": "ok",
                                        "uptime_s": int(time.time() - STARTED_AT)})
        self.send_json(404, {"error": {"code": "not_found",
                                       "message": "есть /received и /health"}})

    def do_POST(self):  # noqa: N802
        if self.path == "/_reset":
            RECEIVED.clear()
            return self.send_json(200, {"reset": True})
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"_raw": raw.decode(errors="replace")}
        delivery = {"received_at": now_iso(), "path": self.path,
                    "payload": payload}
        RECEIVED.append(delivery)
        print(f"[sink] delivery #{len(RECEIVED)}: "
              f"{json.dumps(payload, ensure_ascii=False)[:120]}", flush=True)
        self.send_json(200, {"accepted": True, "delivery": len(RECEIVED)})


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[webhook-sink] listening on :{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
