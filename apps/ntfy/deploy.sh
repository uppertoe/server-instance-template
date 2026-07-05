#!/usr/bin/env bash
# Release hook for the self-hosted ntfy push server. Run from the repo root by
# the ~/deploy helper. Idempotent.
set -euo pipefail

# Start ntfy through compose so the digest-pinned ntfy-init service owns the
# volume-permission fix. Do not use ad-hoc helper images here; CI only enforces
# image pinning and runtime controls for declared compose services.
docker compose up -d --wait ntfy

# Bootstrap the admin user (password from apps/ntfy/.env) if it is missing.
# Idempotent by attempting the add and tolerating the "already exists" outcome,
# rather than pre-checking `ntfy user list`: just after the force-recreate above
# the container can answer an empty list before its auth DB is ready, which would
# make the pre-check spuriously add and then abort the whole deploy (set -e).
if [ -f apps/ntfy/.env ]; then
  set -a
  # shellcheck disable=SC1091
  . apps/ntfy/.env
  set +a
fi
if [ -n "${NTFY_ADMIN_PASSWORD:-}" ]; then
  if add_out=$(docker compose exec -T -e "NTFY_PASSWORD=${NTFY_ADMIN_PASSWORD}" ntfy \
        ntfy user add --role=admin admin 2>&1); then
    echo "Created ntfy admin user."
  elif printf '%s' "$add_out" | grep -qi 'already exists'; then
    echo "ntfy admin user already present."
  else
    printf '%s\n' "$add_out" >&2
    exit 1
  fi
fi

cat <<'EOF'
ntfy is up. To finish wiring on-box alerts:
  1. Create a publish token:   docker compose exec ntfy ntfy token add admin
  2. Put it in the notify role config on the host:
       /etc/vps-scaffold/notify.env  ->  NTFY_TOKEN=<token>
       NTFY_URL=http://127.0.0.1:8080/<your-topic>
     (or set notify_ntfy_url / notify_ntfy_token in the inventory and re-run
      the notify role).
  3. For phone delivery: point DNS for ntfy.<DOMAIN> at this host, then
     `mv apps/ntfy/ntfy.caddy.disabled apps/ntfy/ntfy.caddy` and redeploy; then
     subscribe in the ntfy app with the token.
  4. SINGLE-BOX CAVEAT: ntfy runs on the host it monitors, so it cannot alert
     when the host itself is down. Add an external dead-man's-switch
     (e.g. Healthchecks.io) — see apps/ntfy/README.md.
EOF
