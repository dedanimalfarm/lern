"""
producer — генератор синтетических финансовых транзакций для Kafka.
Async loop публикует JSON-события в topic `raw-feeds` с настраиваемым rate.
"""
import os
import asyncio
import json
import random
import uuid
from datetime import datetime, timezone
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import Response
from aiokafka import AIOKafkaProducer
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

SERVICE_NAME = os.environ.get("SERVICE_NAME", "producer")
VERSION = os.environ.get("VERSION", "0.1.0")
KAFKA_BOOTSTRAP_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
KAFKA_TOPIC = os.environ.get("KAFKA_TOPIC", "raw-feeds")
RATE_PER_SEC = float(os.environ.get("RATE_PER_SEC", "10"))

CURRENCIES = ["USD", "EUR", "GBP", "JPY"]
PAYMENT_METHODS = ["card", "bank", "wallet"]

EVENTS_PRODUCED = Counter(
    "aegis_events_produced_total", "Total events published to Kafka", ["service", "topic"]
)
EVENTS_FAILED = Counter(
    "aegis_events_failed_total", "Total publish failures", ["service", "topic"]
)

kafka_producer: AIOKafkaProducer | None = None
producer_task: asyncio.Task | None = None


def generate_event() -> dict:
    """Один синтетический payment event с UUID, рандомными полями."""
    return {
        "transaction_id": str(uuid.uuid4()),
        "merchant_id": f"merchant-{random.randint(1, 100)}",
        "customer_id": f"customer-{random.randint(1, 10000)}",
        "amount": round(random.uniform(1.0, 10000.0), 2),
        "currency": random.choice(CURRENCIES),
        "payment_method": random.choice(PAYMENT_METHODS),
        "occurred_at": datetime.now(timezone.utc).isoformat(),
    }


async def producer_loop():
    """Бесконечный async loop: генерим событие, шлём в Kafka, спим по rate."""
    interval = 1.0 / RATE_PER_SEC if RATE_PER_SEC > 0 else 1.0
    while True:
        event = generate_event()
        try:
            await kafka_producer.send_and_wait(
                KAFKA_TOPIC, json.dumps(event).encode("utf-8")
            )
            EVENTS_PRODUCED.labels(service=SERVICE_NAME, topic=KAFKA_TOPIC).inc()
        except Exception:
            EVENTS_FAILED.labels(service=SERVICE_NAME, topic=KAFKA_TOPIC).inc()
        await asyncio.sleep(interval)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global kafka_producer, producer_task
    kafka_producer = AIOKafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS)
    await kafka_producer.start()
    producer_task = asyncio.create_task(producer_loop())
    yield
    producer_task.cancel()
    try:
        await producer_task
    except asyncio.CancelledError:
        pass
    await kafka_producer.stop()


app = FastAPI(title=SERVICE_NAME, version=VERSION, lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok", "service": SERVICE_NAME, "version": VERSION}


@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
