# Project 5 — Monitoring & Logging System

A fully runnable observability stack using **ELK Stack + Prometheus + Grafana + Alertmanager**, orchestrated with Docker Compose.

---

## What's Inside

| Service        | Purpose                              | URL                        |
|----------------|--------------------------------------|----------------------------|
| Elasticsearch  | Log storage and search               | http://localhost:9200      |
| Logstash       | Log ingestion pipeline               | port 5044 (Beats), 5000 (TCP) |
| Kibana         | Log dashboards and search UI         | http://localhost:5601      |
| Prometheus     | Metrics collection and storage       | http://localhost:9090      |
| Grafana        | Metrics dashboards and alerts        | http://localhost:3000      |
| Alertmanager   | Alert routing (Slack, email, etc.)   | http://localhost:9093      |
| Node Exporter  | Host CPU/memory/disk metrics         | http://localhost:9100      |
| Sample App     | Flask app with Prometheus metrics    | http://localhost:8000      |

---

## Requirements

- Docker Engine 24+
- Docker Compose 2.20+
- 8 GB RAM minimum (16 GB recommended)
- 20 GB free disk space

---

## How to Run

### Option 1 — Automated setup (recommended)

```bash
chmod +x setup.sh
bash setup.sh
```

This script:
1. Checks Docker and memory requirements
2. Sets `vm.max_map_count` for Elasticsearch
3. Pulls all images and builds the sample app
4. Starts all services
5. Waits for Elasticsearch to become healthy
6. Sets up the `kibana_system` user
7. Prints all service URLs

---

### Option 2 — Manual step-by-step

```bash
# 1. Required kernel setting for Elasticsearch
sudo sysctl -w vm.max_map_count=262144

# 2. Copy environment file and set your passwords
cp .env .env.backup   # Already pre-filled with defaults

# 3. Pull images
docker compose pull

# 4. Build and start everything
docker compose up -d --build

# 5. Watch logs (Ctrl+C to exit, services keep running)
docker compose logs -f

# 6. Set the kibana_system password (after Elasticsearch is healthy)
curl -X POST -u "elastic:changeme123" \
  http://localhost:9200/_security/user/kibana_system/_password \
  -H "Content-Type: application/json" \
  -d '{"password":"changeme123"}'
```

---

## Default Credentials

| Service       | Username  | Password     |
|---------------|-----------|--------------|
| Kibana        | elastic   | changeme123  |
| Grafana       | admin     | admin123     |
| Elasticsearch | elastic   | changeme123  |

> Change these in `.env` before deploying anywhere public.

---

## Run Validation Tests

After the stack is running:

```bash
chmod +x test.sh
bash test.sh
```

This checks all 20 things: service health, Prometheus targets, metrics collection, log ingestion, and sample app endpoints.

---

## Send a Test Log

```bash
# Send JSON log to Logstash TCP input
echo '{"level":"ERROR","message":"Test error","service":"my-app"}' | nc localhost 5000

# Verify it landed in Elasticsearch
curl -s -u elastic:changeme123 \
  'http://localhost:9200/logs-*/_search?q=level:ERROR&pretty' | head -30
```

---

## Kibana — View Logs

1. Open http://localhost:5601
2. Login: `elastic` / `changeme123`
3. Go to **Stack Management → Data Views → Create data view**
4. Pattern: `logs-*`, Time field: `@timestamp`
5. Go to **Discover** to search and filter logs

---

## Grafana — View Metrics

1. Open http://localhost:3000
2. Login: `admin` / `admin123`
3. The **System Overview** dashboard is pre-loaded automatically
4. Shows: CPU, memory, HTTP request rate, error rate, p95 latency

---

## Prometheus — Query Metrics

Open http://localhost:9090 and try these queries:

```promql
# CPU usage %
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage %
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# HTTP error rate
rate(http_requests_total{status=~"5.."}[5m])

# p95 response time
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

---

## Enable Slack Alerts

1. Create a Slack webhook at https://api.slack.com/messaging/webhooks
2. Edit `alertmanager/alertmanager.yml`
3. Uncomment the `slack_configs` section and paste your webhook URL
4. Reload Alertmanager:

```bash
curl -X POST http://localhost:9093/-/reload
```

---

## Useful Commands

```bash
# Check all container statuses
docker compose ps

# Stream logs from all services
docker compose logs -f

# Stream logs from one service
docker compose logs -f kibana

# Restart a single service
docker compose restart grafana

# Stop everything (data is preserved)
docker compose down

# Stop and DELETE all data volumes
docker compose down -v

# Reload Prometheus config without restart
curl -X POST http://localhost:9090/-/reload
```

---

## Project Structure

```
monitoring-project/
├── docker-compose.yml          # All services wired together
├── .env                        # Passwords and versions
├── setup.sh                    # One-shot setup script
├── test.sh                     # Validation test suite
├── elasticsearch/
│   └── elasticsearch.yml
├── logstash/
│   ├── logstash.yml
│   └── pipeline/logstash.conf  # Parse and route logs
├── kibana/
│   └── kibana.yml
├── prometheus/
│   ├── prometheus.yml           # Scrape targets
│   └── rules/alert-rules.yml   # CPU/memory/error alerts
├── alertmanager/
│   └── alertmanager.yml        # Slack routing
├── grafana/
│   ├── provisioning/           # Auto-loads datasources & dashboards
│   └── dashboards/overview.json
├── filebeat/
│   └── filebeat.yml            # Ships Docker container logs
└── sample-app/
    ├── app.py                  # Flask app with Prometheus metrics
    ├── Dockerfile
    └── requirements.txt
```
