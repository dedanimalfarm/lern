"""
tx-writer — consumer для Kafka topic `raw-feeds` → PG таблица `transactions`.
Идемпотентная запись через ON CONFLICT (Kafka at-least-once delivery).
"""
import os
import json
import asyncio
import logging
import uuid as uuid_lib
from datetime import datetime
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import Response
from aiokafka import AIOKafkaConsumer
import asyncpg
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("tx-writer")

SERVICE_NAME = os.environ.get("SERVICE_NAME", "tx-writer")
VERSION = os.environ.get("VERSION", "0.1.0")
KAFKA_BOOTSTRAP_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
KAFKA_TOPIC = os.environ.get("KAFKA_TOPIC", "raw-feeds")
KAFKA_GROUP_ID = os.environ.get("KAFKA_GROUP_ID", "tx-writer")

PG_DSN = (
    f"postgres://{os.environ['POSTGRES_USER']}:{os.environ['POSTGRES_PASSWORD']}"
    f"@{os.environ['POSTGRES_HOST']}:{os.environ.get('POSTGRES_PORT', '5432')}"
    f"/{os.environ['POSTGRES_DB']}"
)

SCHEMA_DDL = """
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id  UUID PRIMARY KEY,
    merchant_id     VARCHAR(64) NOT NULL,
    customer_id     VARCHAR(64) NOT NULL,
    amount          NUMERIC(12, 2) NOT NULL,
    currency        CHAR(3) NOT NULL,
    payment_method  VARCHAR(32) NOT NULL,
    occurred_at     TIMESTAMPTZ NOT NULL,
    ingested_at     TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_transactions_occurred_at ON transactions(occurred_at);
"""

INSERT_SQL = """
INSERT INTO transactions
    (transaction_id, merchant_id, customer_id, amount, currency, payment_method, occurred_at)
VALUES ($1, $2, $3, $4, $5, $6, $7)
ON CONFLICT (transaction_id) DO NOTHING
"""

EVENTS_CONSUMED = Counter(
    "aegis_events_consumed_total", "Events consumed from Kafka", ["service", "topic"]
)
EVENTS_WRITTEN = Counter(
    "aegis_events_written_total", "Events written to PG (new rows)", ["service"]
)
EVENTS_SKIPPED = Counter(
    "aegis_events_skipped_total", "Events skipped (duplicate or error)", ["service", "reason"]
)

pg_pool: asyncpg.Pool | None = None
kafka_consumer: AIOKafkaConsumer | None = None
consumer_task: asyncio.Task | None = None


async def consume_loop():
    """Читает Kafka, парсит JSON, идемпотентно вставляет в PG."""
    async for msg in kafka_consumer:
        EVENTS_CONSUMED.labels(service=SERVICE_NAME, topic=KAFKA_TOPIC).inc()
        try:
            event = json.loads(msg.value)
            # Конвертация типов: producer шлёт строки, PG-колонки требуют typed Python objects.
            transaction_id = uuid_lib.UUID(event["transaction_id"])
            occurred_at = datetime.fromisoformat(event["occurred_at"])
            async with pg_pool.acquire() as conn:
                result = await conn.execute(
                    INSERT_SQL,
                    transaction_id,
                    event["merchant_id"],
                    event["customer_id"],
                    event["amount"],
                    event["currency"],
                    event["payment_method"],
                    occurred_at,
                )
            # asyncpg возвращает "INSERT 0 1" если строка вставилась, "INSERT 0 0" если ON CONFLICT.
            if result.endswith(" 1"):
                EVENTS_WRITTEN.labels(service=SERVICE_NAME).inc()
            else:
                EVENTS_SKIPPED.labels(service=SERVICE_NAME, reason="duplicate").inc()
        except (json.JSONDecodeError, KeyError, ValueError) as e:
            EVENTS_SKIPPED.labels(service=SERVICE_NAME, reason=f"parse_{type(e).__name__}").inc()
            log.warning("parse error: %s | payload=%r", e, msg.value[:200])
        except asyncpg.PostgresError as e:
            EVENTS_SKIPPED.labels(service=SERVICE_NAME, reason="pg_error").inc()
            log.error("pg error: %s | event=%s", e, event)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pg_pool, kafka_consumer, consumer_task
    # PG pool + schema bootstrap
    pg_pool = await asyncpg.create_pool(dsn=PG_DSN, min_size=1, max_size=8)
    async with pg_pool.acquire() as conn:
        await conn.execute(SCHEMA_DDL)
    # Kafka consumer
    kafka_consumer = AIOKafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        group_id=KAFKA_GROUP_ID,
        enable_auto_commit=True,
        auto_offset_reset="earliest",
    )
    await kafka_consumer.start()
    consumer_task = asyncio.create_task(consume_loop())
    yield
    consumer_task.cancel()
    try:
        await consumer_task
    except asyncio.CancelledError:
        pass
    await kafka_consumer.stop()
    await pg_pool.close()


app = FastAPI(title=SERVICE_NAME, version=VERSION, lifespan=lifespan)


@app.get("/health")
async def health():
    deps = {}
    try:
        async with pg_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        deps["postgres"] = "ok"
    except Exception as e:
        deps["postgres"] = f"error: {type(e).__name__}"
    return {"status": "ok", "service": SERVICE_NAME, "version": VERSION, "deps": deps}


@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
