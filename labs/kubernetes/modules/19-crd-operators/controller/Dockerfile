# --- builder ---
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# --- runtime ---
FROM python:3.12-slim
RUN useradd -r -u 10001 -m -d /home/operator operator
WORKDIR /app
COPY --from=builder /root/.local /home/operator/.local
COPY webapp_controller.py main.py ./
ENV PATH=/home/operator/.local/bin:$PATH \
    PYTHONUNBUFFERED=1
USER 10001
ENTRYPOINT ["python", "/app/main.py"]
