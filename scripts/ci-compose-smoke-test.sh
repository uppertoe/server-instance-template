#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_APP_DIR="apps/ci-smoke"
CI_OVERRIDE_FILE="docker-compose.ci.override.yml"
BASE_COMPOSE=(docker compose -f docker-compose.yml -f "$CI_OVERRIDE_FILE")

cleanup() {
  "${BASE_COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TEST_APP_DIR"
  rm -f .env docker-compose.override.yml "$CI_OVERRIDE_FILE"
}

wait_for_caddy() {
  local attempts=0
  until "${BASE_COMPOSE[@]}" ps --status running --services | grep -qx "caddy"; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 20 ]]; then
      "${BASE_COMPOSE[@]}" logs caddy || true
      echo "caddy container failed to reach running state" >&2
      return 1
    fi
    sleep 1
  done
}

assert_http_redirect() {
  local expected_host="$1"
  local attempts=0
  local headers=""

  until headers="$(
    curl \
      --silent \
      --show-error \
      --fail \
      --head \
      --header "Host: ${expected_host}" \
      "http://127.0.0.1:18080/" \
      2>/dev/null
  )"; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 20 ]]; then
      "${BASE_COMPOSE[@]}" logs caddy || true
      echo "caddy did not redirect expected host ${expected_host}" >&2
      return 1
    fi
    sleep 1
  done

  grep -i -F "location: https://${expected_host}/" <<<"$headers" >/dev/null
}

assert_https_body() {
  local expected_host="$1"
  local attempts=0
  local body=""

  until body="$(
    curl \
      --silent \
      --show-error \
      --fail \
      --insecure \
      --resolve "${expected_host}:18443:127.0.0.1" \
      "https://${expected_host}:18443/" \
      2>/dev/null
  )"; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 20 ]]; then
      "${BASE_COMPOSE[@]}" logs caddy || true
      echo "caddy did not serve expected host ${expected_host} over HTTPS" >&2
      return 1
    fi
    sleep 1
  done

  [[ "$body" == "ci smoke ok" ]]
}

trap cleanup EXIT
cleanup

mkdir -p "$TEST_APP_DIR"
cat > .env <<'EOF'
DOMAIN=example.com
EOF

cat > "$CI_OVERRIDE_FILE" <<'EOF'
services:
  caddy:
    ports:
      - "18080:80"
      - "18443:443"
      - "18443:443/udp"
EOF

cat > "${TEST_APP_DIR}/ci-smoke.caddy" <<'EOF'
ci.{$DOMAIN} {
    respond "ci smoke ok" 200
}
EOF

echo "Validating standard compose config"
"${BASE_COMPOSE[@]}" config >/dev/null

echo "Starting caddy with production config"
"${BASE_COMPOSE[@]}" up -d caddy >/dev/null
wait_for_caddy
"${BASE_COMPOSE[@]}" exec -T caddy grep -F 'ci.{$DOMAIN}' /tmp/Caddyfile >/dev/null
assert_http_redirect "ci.example.com"

echo "Validating local override config"
cp docker-compose.override.yml.example docker-compose.override.yml
docker compose -f docker-compose.yml -f "$CI_OVERRIDE_FILE" -f docker-compose.override.yml config >/dev/null

echo "Restarting caddy with local override"
docker compose -f docker-compose.yml -f "$CI_OVERRIDE_FILE" -f docker-compose.override.yml up -d caddy >/dev/null
wait_for_caddy
"${BASE_COMPOSE[@]}" exec -T caddy grep -F 'local_certs' /tmp/Caddyfile >/dev/null
assert_https_body "ci.example.com"
