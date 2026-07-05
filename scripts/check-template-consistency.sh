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
require_file ".generated/caddy/apps.caddy"
require_file ".generated/caddy/networks.yml"
require_file ".env.example"
require_file "Caddyfile"
require_file "Caddyfile.local"
require_file "docker-compose.override.yml.example"
require_file "scripts/post-provision-smoke-test.sh"
require_file "apps/auth/docker-compose.yml"
require_file "apps/auth/auth.caddy"
require_file "apps/auth/.env.example"

require_contains "docker-compose.yml" "  - scaffold/docker/caddy.base.yml"
require_contains "docker-compose.yml" "  - .generated/caddy/networks.yml"
require_contains "docker-compose.yml" "  # - apps/auth/docker-compose.yml"
require_contains ".env.example" "DOMAIN=myserver.example.com"
require_contains "Caddyfile.local" "    local_certs"
require_contains "docker-compose.override.yml.example" "      - ./Caddyfile.local:/etc/caddy/Caddyfile:ro"
require_contains "scripts/post-provision-smoke-test.sh" "check_remote \"deploy helper exists and is executable\" \"sudo test -x /home/deploy/deploy\""

require_not_contains "Caddyfile" "import /srv/repo/apps/*/*.caddy"
require_not_contains "Caddyfile.local" "import /srv/repo/apps/*/*.caddy"

# The committed bundle must match its sources (apps/, include list).
bash scripts/check-generated-sync.sh

# Repo tooling must at least parse — cheap insurance for the setup helpers.
for f in scripts/*.sh; do
  bash -n "$f" || fail "bash syntax error in $f"
done
for f in scripts/*.py; do
  python3 -m py_compile "$f" || fail "python syntax error in $f"
done

echo "Template consistency checks passed."
