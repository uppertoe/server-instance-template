#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "required file missing: $path"
}

require_contains() {
  local path="$1"
  local pattern="$2"
  grep -Fqx "$pattern" "$path" || fail "$path is missing expected line: $pattern"
}

require_not_contains() {
  local path="$1"
  local pattern="$2"
  if grep -Fq "$pattern" "$path"; then
    fail "$path contains forbidden text: $pattern"
  fi
}

require_file "docker-compose.yml"
require_file ".env.example"
require_file "Caddyfile"
require_file "Caddyfile.local"
require_file "docker-compose.override.yml.example"
require_file "scripts/post-provision-smoke-test.sh"

require_contains "docker-compose.yml" "  - scaffold/docker/caddy.base.yml"
require_contains ".env.example" "DOMAIN=myserver.example.com"
require_contains "Caddyfile.local" "    local_certs"
require_contains "docker-compose.override.yml.example" "      - ./Caddyfile.local:/etc/caddy/Caddyfile:ro"
require_contains "scripts/post-provision-smoke-test.sh" "check_remote \"~/deploy helper exists and is executable\" \"[[ -x /home/deploy/deploy ]]\""

require_not_contains "Caddyfile" "import /srv/repo/apps/*/*.caddy"
require_not_contains "Caddyfile.local" "import /srv/repo/apps/*/*.caddy"

echo "Template consistency checks passed."
