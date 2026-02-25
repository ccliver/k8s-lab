FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

ENV PYTHONUNBUFFERED=1

# --workers 1 keeps all Prometheus counters in a single process so the
# background checker thread and the /metrics handler share the same state.
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "1", \
     "--threads", "4", \
     "--timeout", "30", \
     "app:app"]
