#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Project 5 — Validation & Test Script
# ─────────────────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

ELASTIC_PASSWORD=$(grep ELASTIC_PASSWORD .env | cut -d= -f2)

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${NC} $desc"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}✘${NC} $desc"
    FAIL=$((FAIL+1))
  fi
}

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Project 5 — Validation Tests"
echo "══════════════════════════════════════════════════════"

echo -e "\n${YELLOW}1. Service Health${NC}"
check "Elasticsearch responds"     curl -sf -u "elastic:${ELASTIC_PASSWORD}" http://localhost:9200
check "Elasticsearch cluster healthy" bash -c "curl -sf -u 'elastic:${ELASTIC_PASSWORD}' http://localhost:9200/_cluster/health | grep -q 'green\|yellow'"
check "Logstash API responds"      curl -sf http://localhost:9600
check "Kibana responds"            curl -sf http://localhost:5601/api/status
check "Prometheus responds"        curl -sf http://localhost:9090/-/ready
check "Alertmanager responds"      curl -sf http://localhost:9093/-/ready
check "Grafana responds"           curl -sf http://localhost:3000/api/health
check "Node Exporter responds"     curl -sf http://localhost:9100/metrics
check "Sample app /health"         curl -sf http://localhost:8000/health

echo -e "\n${YELLOW}2. Prometheus Targets${NC}"
check "Prometheus has targets"     bash -c "curl -sf http://localhost:9090/api/v1/targets | grep -q 'active'"
check "node-exporter target UP"    bash -c "curl -sf 'http://localhost:9090/api/v1/query?query=up{job=\"node-exporter\"}' | grep -q '\"value\":\['"
check "sample-app target UP"       bash -c "curl -sf 'http://localhost:9090/api/v1/query?query=up{job=\"sample-app\"}' | grep -q '\"value\":\['"

echo -e "\n${YELLOW}3. Metrics Collection${NC}"
check "CPU metrics available"      bash -c "curl -sf 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total' | grep -q 'value'"
check "Memory metrics available"   bash -c "curl -sf 'http://localhost:9090/api/v1/query?query=node_memory_MemTotal_bytes' | grep -q 'value'"
check "HTTP request metrics"       bash -c "curl -sf 'http://localhost:9090/api/v1/query?query=http_requests_total' | grep -q 'value'"
check "Alert rules loaded"         bash -c "curl -sf http://localhost:9090/api/v1/rules | grep -q 'HighCPUUsage'"

echo -e "\n${YELLOW}4. Log Ingestion${NC}"
echo '{"level":"INFO","message":"Test log from test.sh","service":"test-runner"}' | nc -q1 localhost 5000 2>/dev/null || true
sleep 2
check "Logs indexed in Elasticsearch" bash -c "curl -sf -u 'elastic:${ELASTIC_PASSWORD}' 'http://localhost:9200/logs-*/_count' | grep -q '\"count\"'"

echo -e "\n${YELLOW}5. Sample App Endpoints${NC}"
check "GET /           returns 200" bash -c "curl -sf http://localhost:8000/ | grep -q 'monitoring-sample-app'"
check "GET /api/data   returns data" bash -c "curl -sf http://localhost:8000/api/data | grep -q 'items\|error'"
check "GET /metrics    returns metrics" bash -c "curl -sf http://localhost:8000/metrics | grep -q 'http_requests_total'"

echo ""
echo "══════════════════════════════════════════════════════"
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}All $TOTAL tests passed!${NC}"
else
  echo -e "  ${GREEN}$PASS passed${NC} / ${RED}$FAIL failed${NC} out of $TOTAL"
fi
echo "══════════════════════════════════════════════════════"
echo ""
