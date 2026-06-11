#!/usr/bin/env python3
"""Helpdesk API — учебный REST-сервер для курса labs/api.

Имитирует API тикет-системы службы поддержки (Service Desk):
CRUD по тикетам, пагинация, фильтры, три режима аутентификации,
rate limiting, вебхуки и управляемые «поломки» (fault injection)
для отработки типовых инцидентов второй линии поддержки.

Только стандартная библиотека Python — никаких pip install.

Конфигурация через переменные окружения:
  PORT        порт HTTP-сервера                      (default: 8080)
  AUTH_MODE   off | apikey | token                   (default: off)
  API_KEY     ключ для режима apikey                 (default: lab-secret-key-2026)
  TOKEN_SECRET секрет подписи HMAC для JWT           (default: lab-hmac-secret)
  TOKEN_TTL   срок жизни токена, секунд              (default: 3600)
  RATE_LIMIT  макс. запросов на IP за 10 секунд, 0=off (default: 0)
  FAULT       none | slow | error500 | badjson | wrongct (default: none)
  WEBHOOK_URL если задан — POST событий ticket.* на этот URL

Запуск:  python3 helpdesk_api.py
"""

import base64
import hashlib
import hmac
import json
import os
import re
import threading
import time
import urllib.request
from collections import defaultdict, deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

# ---------------------------------------------------------------- конфиг

PORT = int(os.environ.get("PORT", "8080"))
AUTH_MODE = os.environ.get("AUTH_MODE", "off")          # off | apikey | token
API_KEY = os.environ.get("API_KEY", "lab-secret-key-2026")
TOKEN_SECRET = os.environ.get("TOKEN_SECRET", "lab-hmac-secret").encode()
TOKEN_TTL = int(os.environ.get("TOKEN_TTL", "3600"))
RATE_LIMIT = int(os.environ.get("RATE_LIMIT", "0"))     # запросов / 10 c, 0 = выкл
WEBHOOK_URL = os.environ.get("WEBHOOK_URL", "")

# Учебные пользователи для режима token (Basic -> Bearer).
# role решает, что можно делать: agent — читать/создавать/менять,
# admin — дополнительно удалять. Так демонстрируется разница 401 vs 403.
USERS = {
    "support": {"password": "support123", "role": "agent"},
    "admin": {"password": "admin123", "role": "admin"},
}

PRIORITIES = ["low", "medium", "high", "critical"]
STATUSES = ["open", "in_progress", "resolved", "closed"]

# ---------------------------------------------------------------- состояние

LOCK = threading.Lock()
STARTED_AT = time.time()


def _seed():
    """Детерминированные стартовые тикеты — чтобы «ожидаемые выводы» в README
    совпадали у всех студентов после POST /api/v1/_lab/reset."""
    rows = [
        ("VPN не подключается из дома", "high", "open",
         "anna.petrova@corp.example", None, "2026-06-01"),
        ("Принтер на 3 этаже печатает пустые листы", "low", "open",
         "oleg.sidorov@corp.example", None, "2026-06-02"),
        ("Не приходят письма от Jira", "medium", "in_progress",
         "maria.ivanova@corp.example", "support", "2026-06-03"),
        ("Ошибка 500 при выгрузке отчёта из CRM", "critical", "in_progress",
         "pavel.smirnov@corp.example", "support", "2026-06-04"),
        ("Нужен доступ к репозиторию gitlab", "medium", "open",
         "ivan.kuznetsov@corp.example", None, "2026-06-05"),
        ("Заблокирована учётная запись AD", "high", "resolved",
         "elena.popova@corp.example", "admin", "2026-06-06"),
        ("Медленно открывается корпоративный портал", "medium", "open",
         "dmitry.volkov@corp.example", None, "2026-06-07"),
        ("Слетела лицензия Office", "low", "closed",
         "olga.morozova@corp.example", "support", "2026-06-08"),
    ]
    tickets = {}
    for i, (title, prio, status, requester, assignee, day) in enumerate(rows, 1):
        ts = f"{day}T09:00:00Z"
        tickets[i] = {
            "id": i, "title": title, "description": "",
            "status": status, "priority": prio,
            "requester": requester, "assignee": assignee,
            "created_at": ts, "updated_at": ts,
        }
    return tickets


TICKETS = _seed()
NEXT_ID = len(TICKETS) + 1
FAULT = os.environ.get("FAULT", "none")
IDEMPOTENCY = {}                  # Idempotency-Key -> (status, body_dict)
RATE_BUCKETS = defaultdict(deque)  # ip -> deque[timestamp]


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------- JWT (HS256)

def _b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _b64u_decode(s: str) -> bytes:
    # base64url без паддинга — дополняем '=' до кратности 4
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def make_token(sub: str, role: str) -> str:
    """Учебный JWT: header.payload.signature, подпись HMAC-SHA256.
    Состояние на сервере не хранится — валидность доказывает подпись."""
    header = _b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    now = int(time.time())
    payload = _b64u(json.dumps(
        {"sub": sub, "role": role, "iat": now, "exp": now + TOKEN_TTL}).encode())
    sig = _b64u(hmac.new(TOKEN_SECRET, f"{header}.{payload}".encode(),
                         hashlib.sha256).digest())
    return f"{header}.{payload}.{sig}"


def check_token(token: str):
    """Возвращает payload либо строку-причину ошибки."""
    parts = token.split(".")
    if len(parts) != 3:
        return None, "malformed_token"
    header, payload, sig = parts
    expect = _b64u(hmac.new(TOKEN_SECRET, f"{header}.{payload}".encode(),
                            hashlib.sha256).digest())
    if not hmac.compare_digest(sig, expect):
        return None, "invalid_signature"
    try:
        claims = json.loads(_b64u_decode(payload))
    except (ValueError, json.JSONDecodeError):
        return None, "malformed_token"
    if claims.get("exp", 0) < time.time():
        return None, "token_expired"
    return claims, None


# ---------------------------------------------------------------- валидация

CREATE_FIELDS = {"title", "description", "priority", "requester"}
PATCH_FIELDS = {"title", "description", "priority", "status", "assignee"}


def validate_ticket_payload(data, allowed):
    """Возвращает список ошибок вида {field, message} — формат, который
    встречается в реальных API: клиент сразу видит ВСЕ проблемы, а не первую."""
    errors = []
    if not isinstance(data, dict):
        return [{"field": "_body", "message": "ожидался JSON-объект"}]
    for field in sorted(set(data) - allowed):
        errors.append({"field": field,
                       "message": f"неизвестное поле (допустимы: {', '.join(sorted(allowed))})"})
    if "title" in data:
        t = data["title"]
        if not isinstance(t, str) or not (3 <= len(t.strip()) <= 200):
            errors.append({"field": "title",
                           "message": "строка длиной от 3 до 200 символов"})
    if "priority" in data and data["priority"] not in PRIORITIES:
        errors.append({"field": "priority",
                       "message": f"допустимые значения: {', '.join(PRIORITIES)}"})
    if "status" in data and data["status"] not in STATUSES:
        errors.append({"field": "status",
                       "message": f"допустимые значения: {', '.join(STATUSES)}"})
    if "requester" in data:
        r = data["requester"]
        if not isinstance(r, str) or "@" not in r:
            errors.append({"field": "requester",
                           "message": "ожидается e-mail (строка с @)"})
    if "description" in data and not isinstance(data["description"], str):
        errors.append({"field": "description", "message": "ожидается строка"})
    if "assignee" in data and data["assignee"] is not None \
            and not isinstance(data["assignee"], str):
        errors.append({"field": "assignee", "message": "строка или null"})
    return errors


# ---------------------------------------------------------------- вебхуки

def fire_webhook(event: str, ticket: dict):
    """Доставка события интеграции. Асинхронно (поток), чтобы медленный
    получатель не тормозил ответ API, — так делают реальные системы."""
    if not WEBHOOK_URL:
        return

    def _send():
        body = json.dumps({"event": event, "ticket": ticket,
                           "sent_at": now_iso()}).encode()
        req = urllib.request.Request(
            WEBHOOK_URL, data=body,
            headers={"Content-Type": "application/json",
                     "User-Agent": "helpdesk-api-webhook/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=3) as resp:
                print(f"[webhook] {event} -> {WEBHOOK_URL} {resp.status}",
                      flush=True)
        except Exception as exc:  # noqa: BLE001 — для лога важна любая причина
            print(f"[webhook] DELIVERY FAILED {event} -> {WEBHOOK_URL}: {exc}",
                  flush=True)

    threading.Thread(target=_send, daemon=True).start()


# ---------------------------------------------------------------- HTTP handler

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "HelpdeskAPI/1.0"

    # ---------- низкоуровневые помощники

    def send_json(self, status: int, obj, extra_headers=None):
        # Реальные API отдают компактный JSON без отступов — поэтому
        # в курсе и нужны jq/Postman, чтобы читать ответы глазами.
        body = json.dumps(obj, ensure_ascii=False,
                          separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra_headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status: int, code: str, message: str,
                        details=None, extra_headers=None):
        err = {"error": {"code": code, "message": message}}
        if details is not None:
            err["error"]["details"] = details
        self.send_json(status, err, extra_headers)

    def read_json_body(self):
        """Читает тело запроса. Возвращает (data, None) или (None, 'sent') —
        если ответ об ошибке уже отправлен."""
        ctype = self.headers.get("Content-Type", "")
        if "application/json" not in ctype:
            self.send_error_json(
                415, "unsupported_media_type",
                f"ожидается Content-Type: application/json, получен: '{ctype or '<нет>'}'")
            return None, "sent"
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw), None
        except json.JSONDecodeError as exc:
            self.send_error_json(
                400, "invalid_json",
                "тело запроса — не валидный JSON",
                {"position": f"line {exc.lineno} column {exc.colno}",
                 "parser": exc.msg})
            return None, "sent"

    def log_message(self, fmt, *args):  # noqa: N802 — сигнатура из stdlib
        # Access-лог в формате, удобном для grep при разборе инцидентов
        print(f"[{now_iso()}] {self.client_address[0]} {fmt % args}",
              flush=True)

    # ---------- сквозные проверки (auth / rate limit / fault)

    def _client_ip(self):
        return self.client_address[0]

    def check_rate_limit(self) -> bool:
        """Скользящее окно 10 с на IP. Возвращает True, если запрос отклонён."""
        if RATE_LIMIT <= 0:
            return False
        bucket = RATE_BUCKETS[self._client_ip()]
        now = time.time()
        while bucket and now - bucket[0] > 10:
            bucket.popleft()
        if len(bucket) >= RATE_LIMIT:
            retry_after = max(1, int(10 - (now - bucket[0])) + 1)
            self.send_error_json(
                429, "rate_limited",
                f"превышен лимит {RATE_LIMIT} запросов за 10 секунд",
                extra_headers={"Retry-After": str(retry_after)})
            return True
        bucket.append(now)
        return False

    def authenticate(self):
        """Возвращает (identity, None) либо (None, 'sent'), если 401 уже отдан.
        identity: {'sub':..., 'role':...} — кто пришёл и что ему можно."""
        if AUTH_MODE == "off":
            return {"sub": "anonymous", "role": "admin"}, None

        if AUTH_MODE == "apikey":
            key = self.headers.get("X-API-Key")
            if key is None:
                self.send_error_json(
                    401, "missing_api_key",
                    "нужен заголовок X-API-Key",
                    extra_headers={"WWW-Authenticate": "ApiKey"})
                return None, "sent"
            if not hmac.compare_digest(key, API_KEY):
                self.send_error_json(
                    401, "invalid_api_key", "ключ не подходит",
                    extra_headers={"WWW-Authenticate": "ApiKey"})
                return None, "sent"
            return {"sub": "apikey-client", "role": "admin"}, None

        # AUTH_MODE == "token": ждём Authorization: Bearer <jwt>
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self.send_error_json(
                401, "missing_token",
                "нужен заголовок Authorization: Bearer <token>; "
                "токен выдаёт POST /api/v1/auth/token",
                extra_headers={"WWW-Authenticate": "Bearer"})
            return None, "sent"
        claims, why = check_token(auth.removeprefix("Bearer ").strip())
        if claims is None:
            self.send_error_json(
                401, why, "токен не принят",
                extra_headers={"WWW-Authenticate": f'Bearer error="{why}"'})
            return None, "sent"
        return {"sub": claims["sub"], "role": claims["role"]}, None

    def apply_fault(self) -> bool:
        """Fault injection для модуля troubleshooting.
        Действует ТОЛЬКО на /api/v1/tickets* — /health остаётся зелёным:
        классическая ситуация «мониторинг ок, а пользователи жалуются»."""
        if FAULT == "slow":
            time.sleep(15)   # дольше типового клиентского таймаута
            return False
        if FAULT == "error500":
            self.send_error_json(500, "internal_error",
                                 "unexpected error, see server logs")
            return True
        if FAULT == "badjson":
            # 200 OK, но тело обрезано — «успех», который ломает парсер клиента
            body = b'{"items":[{"id":1,"title":"VPN ne podkl'
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return True
        if FAULT == "wrongct":
            body = json.dumps({"items": list(TICKETS.values())},
                              ensure_ascii=False).encode()
            self.send_response(200)
            # Неверный Content-Type: строгие клиенты откажутся парсить
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return True
        return False

    # ---------- маршрутизация

    def route(self, method: str):
        global FAULT, NEXT_ID
        # http.server декодирует request line как latin-1; если клиент прислал
        # сырую кириллицу в URL (curl так делает), пересобираем UTF-8 обратно.
        # Percent-encoded ASCII этот roundtrip не трогает.
        raw_path = self.path.encode("iso-8859-1").decode("utf-8", "replace")
        url = urlparse(raw_path)
        path = url.path.rstrip("/") or "/"
        query = parse_qs(url.query)

        # Лимитируем только «боевые» пути: health-чеки и служебные ручки
        # стенда (_lab) не должны съедать квоту — как в реальных API,
        # где /health для балансировщика выведен из-под rate limit.
        if path.startswith("/api/v1/") and "/_lab/" not in path \
                and self.check_rate_limit():
            return

        # --- служебные эндпоинты (без auth и без fault) -----------------
        if path == "/health" and method == "GET":
            return self.send_json(200, {
                "status": "ok",
                "uptime_s": int(time.time() - STARTED_AT)})

        if path == "/" and method == "GET":
            return self.send_json(200, {
                "name": "Helpdesk API (учебный стенд)",
                "version": "v1",
                "docs": "/openapi.yaml",
                "endpoints": ["/health", "/api/v1/tickets",
                              "/api/v1/tickets/{id}", "/api/v1/auth/token",
                              "/api/v1/whoami"]})

        if path == "/openapi.yaml" and method == "GET":
            spec = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "docs", "openapi.yaml")
            try:
                with open(spec, "rb") as f:
                    body = f.read()
            except OSError:
                return self.send_error_json(404, "not_found",
                                            "openapi.yaml не найден на диске")
            self.send_response(200)
            self.send_header("Content-Type", "application/yaml; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        # Управление стендом из verify-скриптов (намеренно вне документации —
        # «внутренняя ручка», в реальных системах такие тоже встречаются)
        if path == "/api/v1/_lab/state" and method == "GET":
            return self.send_json(200, {
                "fault": FAULT, "auth_mode": AUTH_MODE,
                "rate_limit": RATE_LIMIT,
                "webhook_url": WEBHOOK_URL or None,
                "tickets": len(TICKETS)})

        if path == "/api/v1/_lab/fault" and method == "POST":
            data, sent = self.read_json_body()
            if sent:
                return
            mode = (data or {}).get("mode")
            if mode not in ("none", "slow", "error500", "badjson", "wrongct"):
                return self.send_error_json(422, "validation_failed",
                                            "mode: none|slow|error500|badjson|wrongct")
            FAULT = mode
            return self.send_json(200, {"fault": FAULT})

        if path == "/api/v1/_lab/reset" and method == "POST":
            with LOCK:
                TICKETS.clear()
                TICKETS.update(_seed())
                NEXT_ID = len(TICKETS) + 1
                IDEMPOTENCY.clear()
            return self.send_json(200, {"reset": True, "tickets": len(TICKETS)})

        # --- выдача токена (Basic -> Bearer), только в режиме token ------
        if path == "/api/v1/auth/token" and method == "POST":
            if AUTH_MODE != "token":
                return self.send_error_json(
                    404, "not_found",
                    "эндпоинт активен только при AUTH_MODE=token")
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Basic "):
                return self.send_error_json(
                    401, "missing_credentials",
                    "нужен заголовок Authorization: Basic <base64(user:pass)>",
                    extra_headers={"WWW-Authenticate": 'Basic realm="helpdesk"'})
            try:
                user, _, password = base64.b64decode(
                    auth.removeprefix("Basic ")).decode().partition(":")
            except (ValueError, UnicodeDecodeError):
                return self.send_error_json(400, "bad_request",
                                            "не удалось разобрать Basic-кредиты")
            account = USERS.get(user)
            if account is None or account["password"] != password:
                return self.send_error_json(
                    401, "invalid_credentials", "логин или пароль не подходят",
                    extra_headers={"WWW-Authenticate": 'Basic realm="helpdesk"'})
            return self.send_json(200, {
                "access_token": make_token(user, account["role"]),
                "token_type": "Bearer",
                "expires_in": TOKEN_TTL})

        # Старая версия API: учим работать с 3xx — клиент должен уметь
        # ходить за Location (curl -L) и замечать редиректы в логах
        if path.startswith("/api/v0/"):
            target = path.replace("/api/v0/", "/api/v1/", 1)
            return self.send_error_json(
                301, "moved_permanently",
                f"API v0 выведен из эксплуатации, используйте {target}",
                extra_headers={"Location": target})

        # --- всё остальное под /api/v1 требует аутентификации ------------
        if not path.startswith("/api/v1/"):
            return self.send_error_json(404, "not_found",
                                        f"нет такого пути: {path}")

        identity, sent = self.authenticate()
        if sent:
            return

        if path == "/api/v1/whoami" and method == "GET":
            return self.send_json(200, {"sub": identity["sub"],
                                        "role": identity["role"],
                                        "auth_mode": AUTH_MODE})

        # --- /api/v1/tickets[...] ----------------------------------------
        m_list = path == "/api/v1/tickets"
        m_item = re.fullmatch(r"/api/v1/tickets/(\d+)", path)
        if not (m_list or m_item):
            return self.send_error_json(404, "not_found",
                                        f"нет такого пути: {path}")

        if self.apply_fault():
            return

        if m_list:
            if method == "GET":
                return self.list_tickets(query)
            if method == "POST":
                return self.create_ticket(identity)
            return self.send_error_json(
                405, "method_not_allowed",
                f"{method} не поддерживается для /api/v1/tickets",
                extra_headers={"Allow": "GET, POST"})

        ticket_id = int(m_item.group(1))
        if method == "GET":
            return self.get_ticket(ticket_id)
        if method == "PATCH":
            return self.patch_ticket(ticket_id)
        if method == "PUT":
            return self.put_ticket(ticket_id)
        if method == "DELETE":
            return self.delete_ticket(ticket_id, identity)
        return self.send_error_json(
            405, "method_not_allowed",
            f"{method} не поддерживается для /api/v1/tickets/{{id}}",
            extra_headers={"Allow": "GET, PATCH, PUT, DELETE"})

    # ---------- обработчики тикетов

    def list_tickets(self, query):
        items = sorted(TICKETS.values(), key=lambda t: t["id"])
        if "status" in query:
            items = [t for t in items if t["status"] == query["status"][0]]
        if "priority" in query:
            items = [t for t in items if t["priority"] == query["priority"][0]]
        if "q" in query:
            needle = query["q"][0].lower()
            items = [t for t in items if needle in t["title"].lower()]
        try:
            page = max(1, int(query.get("page", ["1"])[0]))
            per_page = min(50, max(1, int(query.get("per_page", ["5"])[0])))
        except ValueError:
            return self.send_error_json(400, "bad_request",
                                        "page и per_page должны быть числами")
        total = len(items)
        start = (page - 1) * per_page
        return self.send_json(200, {
            "items": items[start:start + per_page],
            "page": page, "per_page": per_page,
            "total": total,
            "pages": max(1, -(-total // per_page)),
        }, extra_headers={"X-Total-Count": str(total)})

    def create_ticket(self, identity):
        global NEXT_ID
        # Idempotency-Key: повторный POST с тем же ключом НЕ создаёт дубль,
        # а возвращает сохранённый ответ — защита от ретраев клиента
        idem_key = self.headers.get("Idempotency-Key")
        if idem_key and idem_key in IDEMPOTENCY:
            status, body = IDEMPOTENCY[idem_key]
            return self.send_json(status, body,
                                  extra_headers={"Idempotency-Replayed": "true"})

        data, sent = self.read_json_body()
        if sent:
            return
        errors = validate_ticket_payload(data, CREATE_FIELDS)
        if "title" not in (data or {}):
            errors.append({"field": "title", "message": "обязательное поле"})
        if errors:
            return self.send_error_json(422, "validation_failed",
                                        "тело запроса не прошло валидацию",
                                        errors)
        with LOCK:
            ticket = {
                "id": NEXT_ID,
                "title": data["title"].strip(),
                "description": data.get("description", ""),
                "status": "open",
                "priority": data.get("priority", "medium"),
                "requester": data.get("requester"),
                "assignee": None,
                "created_at": now_iso(),
                "updated_at": now_iso(),
            }
            TICKETS[NEXT_ID] = ticket
            NEXT_ID += 1
        if idem_key:
            IDEMPOTENCY[idem_key] = (201, ticket)
        fire_webhook("ticket.created", ticket)
        return self.send_json(
            201, ticket,
            extra_headers={"Location": f"/api/v1/tickets/{ticket['id']}"})

    def _get_or_404(self, ticket_id):
        ticket = TICKETS.get(ticket_id)
        if ticket is None:
            self.send_error_json(404, "not_found",
                                 f"тикет {ticket_id} не существует")
        return ticket

    def get_ticket(self, ticket_id):
        ticket = self._get_or_404(ticket_id)
        if ticket is not None:
            self.send_json(200, ticket)

    def patch_ticket(self, ticket_id):
        ticket = self._get_or_404(ticket_id)
        if ticket is None:
            return
        data, sent = self.read_json_body()
        if sent:
            return
        errors = validate_ticket_payload(data, PATCH_FIELDS)
        if errors:
            return self.send_error_json(422, "validation_failed",
                                        "тело запроса не прошло валидацию",
                                        errors)
        with LOCK:
            old_status = ticket["status"]
            ticket.update(data)
            ticket["updated_at"] = now_iso()
        if "status" in data and data["status"] != old_status:
            fire_webhook("ticket.status_changed", ticket)
        return self.send_json(200, ticket)

    def put_ticket(self, ticket_id):
        """PUT = ПОЛНАЯ замена представления: всё, что не прислали,
        сбрасывается к дефолтам. Это намеренно — в модуле 03 на этом
        строится урок «чем PUT опасен и когда нужен PATCH»."""
        ticket = self._get_or_404(ticket_id)
        if ticket is None:
            return
        data, sent = self.read_json_body()
        if sent:
            return
        errors = validate_ticket_payload(data, PATCH_FIELDS | {"requester"})
        if "title" not in (data or {}):
            errors.append({"field": "title", "message": "обязательное поле"})
        if errors:
            return self.send_error_json(422, "validation_failed",
                                        "тело запроса не прошло валидацию",
                                        errors)
        with LOCK:
            old_status = ticket["status"]
            replaced = {
                "id": ticket["id"],
                "title": data["title"].strip(),
                "description": data.get("description", ""),
                "status": data.get("status", "open"),
                "priority": data.get("priority", "medium"),
                "requester": data.get("requester"),
                "assignee": data.get("assignee"),
                "created_at": ticket["created_at"],
                "updated_at": now_iso(),
            }
            TICKETS[ticket_id] = replaced
        if replaced["status"] != old_status:
            fire_webhook("ticket.status_changed", replaced)
        return self.send_json(200, replaced)

    def delete_ticket(self, ticket_id, identity):
        # 403 ≠ 401: пользователь ОПОЗНАН, но прав не хватает
        if identity["role"] != "admin":
            return self.send_error_json(
                403, "forbidden",
                f"роль '{identity['role']}' не может удалять тикеты "
                "(нужна роль admin)")
        ticket = self._get_or_404(ticket_id)
        if ticket is None:
            return
        with LOCK:
            TICKETS.pop(ticket_id, None)
        fire_webhook("ticket.deleted", ticket)
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ---------- глаголы HTTP -> общий роутер

    def do_GET(self):     # noqa: N802
        self.route("GET")

    def do_POST(self):    # noqa: N802
        self.route("POST")

    def do_PATCH(self):   # noqa: N802
        self.route("PATCH")

    def do_PUT(self):     # noqa: N802
        self.route("PUT")

    def do_DELETE(self):  # noqa: N802
        self.route("DELETE")

    def do_HEAD(self):    # noqa: N802
        # HEAD = GET без тела; отвечаем только на /health
        if urlparse(self.path).path == "/health":
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            self.send_response(405)
            self.send_header("Content-Length", "0")
            self.end_headers()


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[helpdesk-api] listening on :{PORT} "
          f"auth={AUTH_MODE} rate_limit={RATE_LIMIT} fault={FAULT} "
          f"webhook={'on' if WEBHOOK_URL else 'off'}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
