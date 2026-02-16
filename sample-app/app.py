import time
import random
import logging
from flask import Flask, jsonify, request
from prometheus_client import (
    Counter, Histogram, Gauge,
    generate_latest, CONTENT_TYPE_LATEST
)

app = Flask(__name__)

# ── Structured logging ────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s"
)
logger = logging.getLogger(__name__)

# ── Prometheus metrics ────────────────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests received",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)
ACTIVE_REQUESTS = Gauge(
    "active_requests",
    "Number of active requests being processed"
)
ERRORS_TOTAL = Counter(
    "application_errors_total",
    "Total application errors",
    ["type"]
)


# ── Request lifecycle hooks ───────────────────────────────────────────────────
@app.before_request
def before_request():
    ACTIVE_REQUESTS.inc()
    request._start_time = time.time()


@app.after_request
def after_request(response):
    ACTIVE_REQUESTS.dec()
    latency = time.time() - request._start_time
    REQUEST_LATENCY.labels(request.method, request.path).observe(latency)
    REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    logger.info(
        f"{request.method} {request.path} "
        f"status={response.status_code} "
        f"duration={latency:.4f}s"
    )
    return response


# ── Routes ────────────────────────────────────────────────────────────────────
@app.route("/metrics")
def metrics():
    """Prometheus scrape endpoint."""
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/health")
def health():
    """Health check endpoint."""
    return jsonify({"status": "healthy", "timestamp": time.time()})


@app.route("/api/data")
def get_data():
    """Simulates a real endpoint with variable latency and occasional errors."""
    # Simulate realistic latency (10ms – 300ms)
    time.sleep(random.uniform(0.01, 0.3))

    # Simulate ~3% error rate
    if random.random() < 0.03:
        ERRORS_TOTAL.labels(type="internal").inc()
        logger.error("Simulated internal server error on /api/data")
        return jsonify({"error": "Internal server error"}), 500

    count = random.randint(1, 100)
    logger.info(f"Returning {count} items from /api/data")
    return jsonify({"status": "ok", "items": count, "timestamp": time.time()})


@app.route("/api/slow")
def slow_endpoint():
    """Simulates a slow endpoint to trigger latency alerts."""
    delay = random.uniform(1.5, 3.5)
    time.sleep(delay)
    logger.warning(f"Slow response on /api/slow — took {delay:.2f}s")
    return jsonify({"status": "ok", "delay": round(delay, 2)})


@app.route("/api/error")
def force_error():
    """Forces a 500 error — useful for testing alerts."""
    ERRORS_TOTAL.labels(type="forced").inc()
    logger.error("Forced error triggered on /api/error")
    return jsonify({"error": "Forced error for testing"}), 500


@app.route("/")
def index():
    return jsonify({
        "app": "monitoring-sample-app",
        "endpoints": ["/health", "/metrics", "/api/data", "/api/slow", "/api/error"]
    })


# ── Background traffic simulator ──────────────────────────────────────────────
import threading
import urllib.request

def generate_traffic():
    """Generates background traffic so dashboards have live data."""
    time.sleep(10)  # Wait for app to fully start
    endpoints = ["/api/data"] * 8 + ["/api/slow"] * 1 + ["/api/error"] * 1
    while True:
        try:
            ep = random.choice(endpoints)
            urllib.request.urlopen(f"http://localhost:8000{ep}", timeout=5)
        except Exception:
            pass
        time.sleep(random.uniform(0.5, 2.0))


if __name__ == "__main__":
    t = threading.Thread(target=generate_traffic, daemon=True)
    t.start()
    logger.info("Sample app starting on port 8000")
    app.run(host="0.0.0.0", port=8000, debug=False)
