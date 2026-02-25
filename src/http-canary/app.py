import os
import time
import threading
import logging

import requests
from flask import Flask, Response
from prometheus_client import (
    Counter,
    Gauge,
    Histogram,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

CANARY_URLS: list[str] = [
    u.strip() for u in os.environ.get("CANARY_URLS", "").split(",") if u.strip()
]
CHECK_INTERVAL = int(os.environ.get("CHECK_INTERVAL", "30"))
REQUEST_TIMEOUT = int(os.environ.get("REQUEST_TIMEOUT", "10"))

RESPONSE_TIME = Histogram(
    "http_canary_response_time_seconds",
    "HTTP request duration in seconds",
    ["url"],
    buckets=[0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0],
)

REQUESTS_TOTAL = Counter(
    "http_canary_requests_total",
    "Total HTTP canary requests by URL and status",
    ["url", "status"],
)

CANARY_UP = Gauge(
    "http_canary_up",
    "1 if the target URL returned a 2xx response, 0 otherwise",
    ["url"],
)

LAST_SUCCESS_TS = Gauge(
    "http_canary_last_success_timestamp",
    "Unix timestamp of the last successful (2xx) check",
    ["url"],
)

# Initialise gauges so all configured URLs appear in /metrics immediately,
# even before the first check completes.
for _url in CANARY_URLS:
    CANARY_UP.labels(url=_url).set(0)
    LAST_SUCCESS_TS.labels(url=_url).set(0)


def check_url(url: str) -> None:
    start = time.monotonic()
    try:
        resp = requests.get(url, timeout=REQUEST_TIMEOUT)
        duration = time.monotonic() - start
        status = str(resp.status_code)

        RESPONSE_TIME.labels(url=url).observe(duration)
        REQUESTS_TOTAL.labels(url=url, status=status).inc()

        if resp.ok:
            CANARY_UP.labels(url=url).set(1)
            LAST_SUCCESS_TS.labels(url=url).set(time.time())
        else:
            CANARY_UP.labels(url=url).set(0)

        logger.info("checked %s status=%s duration=%.3fs", url, status, duration)

    except requests.RequestException as exc:
        duration = time.monotonic() - start

        RESPONSE_TIME.labels(url=url).observe(duration)
        REQUESTS_TOTAL.labels(url=url, status="error").inc()
        CANARY_UP.labels(url=url).set(0)

        logger.warning("check failed %s error=%s duration=%.3fs", url, exc, duration)


def run_checks() -> None:
    """Background loop: check every URL, sleep, repeat."""

    logger.info(
        "canary checker started urls=%d interval=%ds", len(CANARY_URLS), CHECK_INTERVAL
    )
    while True:
        for url in CANARY_URLS:
            check_url(url)
        time.sleep(CHECK_INTERVAL)


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route("/health")
def health():
    return {"status": "ok"}, 200


# ---------------------------------------------------------------------------
# Start background thread
# gunicorn must use --workers 1 so only one process owns the checker thread
# and the in-process metric counters remain consistent.
# ---------------------------------------------------------------------------
if CANARY_URLS:
    _thread = threading.Thread(target=run_checks, daemon=True)
    _thread.start()
else:
    logger.warning("CANARY_URLS is not set; no checks will run")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
