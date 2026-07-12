#!/usr/bin/env bash
# Release hook for the Authelia OIDC provider. Run from the repo root by the
# ~/deploy helper. Idempotent.
set -euo pipefail

# 1. Admin-maintained user list. It lives in a directory-mounted folder
#    (apps/authelia/users/) so the invite portal's atomic temp+rename write
#    hot-reloads in Authelia (a single-file bind mount would pin the inode --
#    see docker-compose.yml). The directory must exist and be uid-1000-owned
#    BEFORE `up`, or Docker creates the bind-mount source as root and Authelia
#    (uid 1000) can't write it.
users_dir=apps/authelia/users
mkdir -p "$users_dir"
# MIGRATE an existing pre-directory users_database.yml into users/ -- MOVE it,
# never reseed. deploy.sh must not fall through to the example here: the example
# is a disabled placeholder, so reseeding a live deployment would lock every
# user out of SSO.
if [ -f apps/authelia/users_database.yml ] && [ ! -f "$users_dir/users_database.yml" ]; then
  mv apps/authelia/users_database.yml "$users_dir/users_database.yml"
  echo "Migrated apps/authelia/users_database.yml -> $users_dir/ (directory layout)."
fi
# Seed from the example only on a genuinely fresh install (no user list in
# either the old or new location).
if [ ! -f "$users_dir/users_database.yml" ]; then
  cp apps/authelia/users_database.yml.example "$users_dir/users_database.yml"
  echo "Seeded $users_dir/users_database.yml from the example -- edit it to add real users."
fi
# Per-client OIDC secret hashes are mounted as files (they contain '$', which
# Compose would interpolate away in env values). Seed any missing *.hash from
# its .example so Authelia loads cleanly; replace the placeholder with the real
# Digest (see README "Adding an OIDC client").
for ex in apps/authelia/secrets/*.hash.example; do
  [ -e "$ex" ] || continue
  real="${ex%.example}"
  if [ ! -f "$real" ]; then
    cp "$ex" "$real"
    echo "Seeded ${real} from the example -- paste the real pbkdf2 Digest before clients can authenticate."
  fi
done
chmod 700 "$users_dir" 2>/dev/null || true
chmod 600 "$users_dir/users_database.yml" apps/authelia/.env apps/authelia/secrets/*.hash 2>/dev/null || true
# Self-service reset AND the invite portal write into users/, so Authelia (uid
# 1000) must own the whole directory (its contents plus the portal's runtime
# .bak/.tmp/.portal.lock siblings). chown via a root busybox container (the
# deploy user can't chown to another uid). Runs EVERY deploy (idempotent): in
# restricted mode a sudo/root hand-edit could otherwise leave a file the portal
# and Authelia can't rewrite. No-op when the deploy user is already uid 1000.
docker run --rm -v "$PWD/apps/authelia:/m" busybox:latest@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d chown -R 1000:1000 /m/users 2>/dev/null || true
# The OIDC client-secret hashes are mounted :ro and read by Authelia (uid 1000).
# A hash auto-seeded from *.example above runs under the (root) deploy wrapper, so
# the new file is root-owned and mode 600 -- unreadable by uid 1000, which makes
# Authelia fail to load its whole config (a template `secret` error) and crash the
# provider. chown them to 1000 too, same as users/ above. Idempotent; no-op when
# the deploy user is already uid 1000.
docker run --rm -v "$PWD/apps/authelia:/m" busybox:latest@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d sh -c 'chown 1000:1000 /m/secrets/*.hash' 2>/dev/null || true

# 2. Create the named volumes (this also pulls in the authelia-redis dependency,
#    creating its volume). Both may crash-loop until the perms/key below exist --
#    expected and handled.
docker compose up -d authelia || true

# 2b. Session store: authelia-redis runs as 999:999 with a read-only rootfs and
#     persists its append-only file to the authelia_redis_data volume, which is
#     root-owned on creation -> chown so Redis can write it, then recreate so it
#     comes up healthy (Authelia depends_on it and won't start until it is).
redis_vol="$(docker volume ls -q | grep -E '_authelia_redis_data$' | head -1)"
if [ -n "$redis_vol" ]; then
  docker run --rm -v "${redis_vol}:/data" busybox:latest@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d chown -R 999:999 /data
  docker compose up -d --force-recreate authelia-redis
fi

# 3. Named volumes are root-owned on creation; Authelia runs as 1000:1000
#    (CIS §5) and must read/write /data. chown via a plain busybox:latest@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d container.
data_vol="$(docker volume ls -q | grep -E '_authelia_data$' | head -1)"
docker run --rm -v "${data_vol}:/data" busybox:latest@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d chown -R 1000:1000 /data

# 4. Generate the OIDC issuer signing key once (RSA-4096), kept on the data
#    volume and never committed. configuration.yml loads it via fileContent.
if ! docker run --rm -v "${data_vol}:/data" busybox:latest@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d test -f /data/oidc.key.pem; then
  docker run --rm -v "${data_vol}:/data" --user 1000:1000 alpine/openssl:latest@sha256:87adbe7a8c904b825b9068d5a4060799b1e8280c67a64684f72cef376f627a46 \
    genrsa -out /data/oidc.key.pem 4096
  docker run --rm -v "${data_vol}:/data" busybox:latest@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d chmod 600 /data/oidc.key.pem
  echo "Generated OIDC issuer key at /data/oidc.key.pem (on the authelia_data volume)."
fi

# 5. Recreate now that the key and permissions are in place.
docker compose up -d --force-recreate authelia

cat <<'EOF'
Authelia is up on sso.<DOMAIN>. Next:
  1. Add users to apps/authelia/users/users_database.yml (or, once apps/users
     is deployed, use the invite portal instead of hand-editing). Hash a
     password with:
       docker compose run --rm authelia \
         authelia crypto hash generate argon2 --password 'the-password'
     Put users in the groups that gate the apps they may use (e.g. cms-editors
     for the CMS commit broker) -- see apps/authelia/README.md.
  2. Wire an OIDC client (cms-auth is pre-registered): mint its secret pair with
       docker compose run --rm authelia \
         authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72
     -> "Random Password" goes in the app's .env (OIDC_CLIENT_SECRET),
        "Digest" goes in apps/authelia/secrets/<client>.hash (one line), then redeploy.
  3. Point DNS for sso.<DOMAIN> at this host so Caddy can issue its certificate.
EOF
