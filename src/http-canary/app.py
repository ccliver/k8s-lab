import os
import time
import threading
import logging

import boto3
import requests
from flask import Flask

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
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
CW_NAMESPACE = os.environ.get("CW_NAMESPACE", "k8s-lab/HttpCanary")

cloudwatch = boto3.client("cloudwatch", region_name=AWS_REGION)


def put_metrics(url: str, duration: float, up: int) -> None:
    cloudwatch.put_metric_data(
        Namespace=CW_NAMESPACE,
        MetricData=[
            {
                "MetricName": "ResponseTime",
                "Dimensions": [{"Name": "URL", "Value": url}],
                "Value": duration,
                "Unit": "Seconds",
            },
            {
                "MetricName": "Up",
                "Dimensions": [{"Name": "URL", "Value": url}],
                "Value": up,
                "Unit": "Count",
            },
        ],
    )


def check_url(url: str) -> None:
    start = time.monotonic()
    try:
        resp = requests.get(url, timeout=REQUEST_TIMEOUT)
        duration = time.monotonic() - start
        up = 1 if resp.ok else 0
        put_metrics(url, duration, up)
        logger.info("checked %s status=%s duration=%.3fs", url, resp.status_code, duration)
    except requests.RequestException as exc:
        duration = time.monotonic() - start
        put_metrics(url, duration, 0)
        logger.warning("check failed %s error=%s duration=%.3fs", url, exc, duration)


def run_checks() -> None:
    logger.info(
        "canary checker started urls=%d interval=%ds", len(CANARY_URLS), CHECK_INTERVAL
    )
    while True:
        for url in CANARY_URLS:
            check_url(url)
        time.sleep(CHECK_INTERVAL)


@app.route("/health")
def health():
    return {"status": "ok"}, 200


if CANARY_URLS:
    _thread = threading.Thread(target=run_checks, daemon=True)
    _thread.start()
else:
    logger.warning("CANARY_URLS is not set; no checks will run")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
