# Multi-stage build for Python Worker service
FROM python:3.11-slim AS builder

WORKDIR /app

# Install dependencies to /install prefix
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Final stage
FROM python:3.11-slim

WORKDIR /app

# Copy installed dependencies from builder to /usr/local (system-wide)
COPY --from=builder /install /usr/local

# Copy application code
COPY app.py .

# Create non-root user and set ownership
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8081

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:8081", "--workers", "2", "--timeout", "60", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
