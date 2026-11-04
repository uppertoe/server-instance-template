#!/usr/bin/env bash
# One-time setup for the cms-auth CMS commit broker. Run from the repo root:
#   bash apps/cms-auth/setup.sh
#
# Automates everything machine-doable when enabling the CMS on a server:
#   - generates SESSION_SECRET, and the gateway secret (root .env) that Caddy
#     injects and the broker checks;
#   - assembles apps/cms-auth/.env (mode 600) from your answers;
#   - base64-encodes the GitHub App private key into the .env;
#   - re-renders the Caddy bundle.
#
# The two steps that inherently need GitHub's UI (creating + installing the App)
# are reduced to opening ONE pre-filled URL and pasting back three values. Put
# your editors in the cms-editors gateway group afterwards (printed at the end).
#
# Idempotent: existing .env values are shown and kept unless you overwrite them.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
app=apps/cms-auth
env_file="$app/.env"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask()  { local p="$1" d="${2:-}" a; if [ -n "$d" ]; then read -rp "$p [$d]: " a; echo "${a:-$d}"; else read -rp "$p: " a; echo "$a"; fi; }

# upsert KEY=VALUE in the .env (replace an existing line or append). Values are
# written verbatim on one line -- fine for base64 / hex / comma lists.
set_env() {
  local key="$1" val="$2"
  touch "$env_file"
  if grep -qE "^${key}=" "$env_file"; then
    # Use a tmp file so any character in val is safe (no sed metachar issues).
    grep -vE "^${key}=" "$env_file" >"$env_file.tmp"
    mv "$env_file.tmp" "$env_file"
  fi
  printf '%s=%s\n' "$key" "$val" >>"$env_file"
}

domain="$(grep -oE '^DOMAIN=.*' .env 2>/dev/null | head -1 | cut -d= -f2- || true)"
[ -n "$domain" ] || domain="$(ask 'DOMAIN (e.g. example.org)')"

say "1/6  GitHub App (the shared bot)"
owner="$(ask 'GitHub owner that will OWN the App (org or user)')"
repos="$(ask 'CMS repo(s), comma-separated owner/name' )"
# Pre-fill the App-creation form: Contents:write only, no webhook, homepage set.
if gh api "/orgs/${owner}" >/dev/null 2>&1; then
  new_app_url="https://github.com/organizations/${owner}/settings/apps/new"
else
  new_app_url="https://github.com/settings/apps/new"
fi
new_app_url="${new_app_url}?name=cms-auth-${domain%%.*}&url=https://cms-auth.${domain}&public=false&webhook_active=false&contents=write&request_oauth_on_install=false"
cat <<EOF

  Open this to create the App (review, then "Create GitHub App"):
    ${new_app_url}

  Then: "Generate a private key" (downloads a .pem), and "Install App" on your
  repo(s). The install URL ends in /installations/<INSTALLATION_ID>.
EOF
app_id="$(ask 'App ID (from the App settings page)')"
install_id="$(ask 'Installation ID (from the install URL)')"
key_pem="$(ask 'Path to the downloaded private-key .pem')"
[ -f "$key_pem" ] || { echo "no such file: $key_pem"; exit 1; }
key_b64="$(base64 <"$key_pem" | tr -d '\n')"

say "2/6  Committer identity (author is the signed-in editor)"
committer_name="$(ask 'Committer name' 'CMS Bot')"
committer_email="$(ask 'Committer email (App bot noreply is ideal)')"

say "3/6  Allowed origins (CMS admin-page origins, comma-separated)"
default_origin="https://handbook.${domain}"
origins="$(ask 'ALLOWED_ORIGINS' "$default_origin")"

say "4/6  Gateway secret (root .env, shared by Caddy and the broker)"
if grep -qE '^CMS_AUTH_GATEWAY_SECRET=.{32,}' .env 2>/dev/null; then
  echo "  kept the existing CMS_AUTH_GATEWAY_SECRET"
else
  grep -vE '^CMS_AUTH_GATEWAY_SECRET=' .env >.env.tmp 2>/dev/null || true
  printf 'CMS_AUTH_GATEWAY_SECRET=%s\n' "$(openssl rand -hex 32)" >>.env.tmp
  mv .env.tmp .env
  chmod 600 .env
  echo "  wrote CMS_AUTH_GATEWAY_SECRET to .env"
fi

say "5/6  Writing $env_file"
set_env ALLOWED_ORIGINS "$origins"
set_env ALLOWED_REPOS "$repos"
set_env GITHUB_APP_ID "$app_id"
set_env GITHUB_APP_INSTALLATION_ID "$install_id"
set_env GITHUB_APP_PRIVATE_KEY_B64 "$key_b64"
set_env COMMITTER_NAME "$committer_name"
set_env COMMITTER_EMAIL "$committer_email"
grep -qE '^SESSION_SECRET=.+' "$env_file" || set_env SESSION_SECRET "$(openssl rand -hex 32)"
chmod 600 "$env_file"
echo "  wrote $env_file (mode 600)"

say "6/6  Re-rendering the Caddy bundle"
bash scaffold/docker/render-caddy-routes.sh >/dev/null
echo "  .generated/caddy updated"

cat <<EOF

Done. Remaining manual step (people, not machines):
  * Put each editor in the 'cms-editors' group on the gateway's admin Groups
    page. Only they can sign in to the CMS.

EOF
if [ -f .sops.yaml ]; then
  # Secrets live in secrets/ (SOPS); the plaintext files written above are
  # gitignored working copies. Encrypt them to the repo's recipients and
  # delete the plaintext once committed. --filename-override makes SOPS pick
  # the recipients rule for the file's final path.
  cat <<EOF
This server keeps its secrets in SOPS (secrets/README.md). Encrypt the two
files written above, commit them signed with apps/cms-auth and .generated,
then delete the plaintext copies:
  mkdir -p secrets/apps/cms-auth
  sops --encrypt --input-type dotenv --output-type dotenv \
    --filename-override secrets/apps/cms-auth/.env.sops $env_file > secrets/apps/cms-auth/.env.sops
  sops --encrypt --input-type dotenv --output-type dotenv \
    --filename-override secrets/.env.sops .env > secrets/.env.sops
If secrets/.env.sops already exists, add CMS_AUTH_GATEWAY_SECRET to it with
  sops --input-type dotenv --output-type dotenv secrets/.env.sops
instead of overwriting it. The next deploy renders both files on the server.
EOF
else
  cat <<EOF
Then commit the tracked changes (apps/cms-auth, .generated) and deploy. The
.env files stay on the server (gitignored).
EOF
fi
