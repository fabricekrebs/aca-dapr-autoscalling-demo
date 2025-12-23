# Multi-stage build for Dashboard service
FROM python:3.11-slim as builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Final stage
FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /install /usr/local
COPY app.py .
COPY templates templates/

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app

USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8082/health', timeout=2)"

EXPOSE 8082

CMD ["gunicorn", "--bind", "0.0.0.0:8082", "--workers", "2", "--timeout", "120", "app:app"]
