#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Project 5 — Monitoring & Logging System — One-Shot Setup Script
# ─────────────────────────────────────────────────────────────────────────────
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

step()  { echo -e "\n${BLUE}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✔ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "${RED}✘ $1${NC}"; exit 1; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Project 5 — Monitoring & Logging System Setup          ║"
echo "║   ELK Stack + Prometheus + Grafana + Alertmanager        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. Prerequisites check ────────────────────────────────────────────────────
step "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || fail "Docker is not installed. Run: curl -fsSL https://get.docker.com | sh"
command -v docker compose >/dev/null 2>&1 || fail "Docker Compose is not installed."

DOCKER_MEM=$(docker info 2>/dev/null | grep -i "total memory" | awk '{print $3}' | cut -d. -f1)
if [ -n "$DOCKER_MEM" ] && [ "$DOCKER_MEM" -lt 6 ]; then
  warn "Docker has less than 6 GB RAM. Elasticsearch may crash. Recommended: 8 GB+"
fi
ok "Docker and Docker Compose found"

# ── 2. vm.max_map_count (required for Elasticsearch) ─────────────────────────
step "Setting vm.max_map_count for Elasticsearch..."
CURRENT_MAP=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if [ "$CURRENT_MAP" -lt 262144 ]; then
  if sudo sysctl -w vm.max_map_count=262144 >/dev/null 2>&1; then
    ok "vm.max_map_count set to 262144"
    # Persist across reboots
    grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null || \
      echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf >/dev/null
  else
    warn "Could not set vm.max_map_count (may need sudo). Elasticsearch might not start."
  fi
else
  ok "vm.max_map_count is already $CURRENT_MAP"
fi

# ── 3. Pull images ────────────────────────────────────────────────────────────
step "Pulling Docker images (this may take a few minutes)..."
docker compose pull --quiet
ok "All images pulled"

# ── 4. Build sample app ───────────────────────────────────────────────────────
step "Building sample app container..."
docker compose build sample-app --quiet
ok "Sample app built"

# ── 5. Start the stack ────────────────────────────────────────────────────────
step "Starting all services..."
docker compose up -d
ok "All containers started"

# ── 6. Wait for Elasticsearch ────────────────────────────────────────────────
step "Waiting for Elasticsearch to become healthy..."
ELASTIC_PASSWORD=$(grep ELASTIC_PASSWORD .env | cut -d= -f2)
MAX_WAIT=120
ELAPSED=0
while true; do
  STATUS=$(curl -s -u "elastic:${ELASTIC_PASSWORD}" http://localhost:9200/_cluster/health 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d: -f2 | tr -d '"')
  if [[ "$STATUS" == "green" || "$STATUS" == "yellow" ]]; then
    ok "Elasticsearch is healthy (status: $STATUS)"
    break
  fi
  if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
    warn "Elasticsearch not healthy after ${MAX_WAIT}s. Check: docker logs elasticsearch"
    break
  fi
  echo -ne "  Waiting... ${ELAPSED}s\r"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

# ── 7. Set kibana_system password ────────────────────────────────────────────
step "Configuring kibana_system user..."
KIBANA_PASSWORD=$(grep KIBANA_PASSWORD .env | cut -d= -f2)
sleep 5
curl -s -X POST -u "elastic:${ELASTIC_PASSWORD}" \
  "http://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}" >/dev/null 2>&1 && ok "kibana_system password set" || warn "Could not set kibana_system password (Kibana may still work)"

# ── 8. Health summary ─────────────────────────────────────────────────────────
step "Checking all services..."
sleep 5
docker compose ps

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✔  STACK IS RUNNING                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}Kibana${NC}         →  http://localhost:5601      (elastic / ${ELASTIC_PASSWORD})"
echo -e "  ${BLUE}Grafana${NC}        →  http://localhost:3000      (admin / $(grep GRAFANA_ADMIN_PASSWORD .env | cut -d= -f2))"
echo -e "  ${BLUE}Prometheus${NC}     →  http://localhost:9090"
echo -e "  ${BLUE}Alertmanager${NC}   →  http://localhost:9093"
echo -e "  ${BLUE}Elasticsearch${NC}  →  http://localhost:9200"
echo -e "  ${BLUE}Sample App${NC}     →  http://localhost:8000"
echo ""
echo -e "  ${YELLOW}Kibana may take 2-3 more minutes to fully initialize.${NC}"
echo ""
echo -e "  ${BLUE}Useful commands:${NC}"
echo -e "    docker compose logs -f          # stream all logs"
echo -e "    docker compose logs -f kibana   # Kibana logs only"
echo -e "    docker compose ps               # container status"
echo -e "    docker compose down             # stop everything"
echo -e "    bash test.sh                    # run validation tests"
echo ""
