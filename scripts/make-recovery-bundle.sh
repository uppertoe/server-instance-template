#!/usr/bin/env bash
# make-recovery-bundle.sh — collect everything NOT in git that a rebuild needs,
# into one encrypted file you store offsite.
#
# The repo rebuilds the box only together with these secrets: the inventory,
# the server/app .env files, and the backup credentials — including the restic
# repository passwords, without which the backups are undecryptable noise.
#
# WHERE TO RUN: on the SERVER, with sudo. That is the only place with the full,
# CURRENT set — the live app .env files under /opt/deploy AND the restic secrets
# under /etc/restic (which are root-only and are NOT in the deploy checkout).
# An operator laptop is often missing app .env files that were only ever edited
# on the box, so a laptop-made bundle can be silently incomplete.
#   ssh <host> 'cd /opt/deploy && sudo scripts/make-recovery-bundle.sh'
#
# Usage:  [DRY_RUN=1] make-recovery-bundle.sh [output-dir]
#   DRY_RUN=1  list what would be bundled, then stop (no passphrase, no file).
# Restore: openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in <bundle> | tar -xzv
#
# Store the bundle somewhere that survives the laptop (a password manager
# attachment, a cloud drive); store the passphrase with it. Re-run after
# rotating any credential. See scaffold/docs/09-recovery.md for the full drill.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Under sudo, default the output to the INVOKING user's home (not /root) and
# hand them the file — otherwise a root-owned bundle they can't scp.
out_dir="${1:-}"
if [[ -z "$out_dir" ]]; then
  if [[ -n "${SUDO_USER:-}" ]]; then out_dir="$(eval echo "~${SUDO_USER}")"; else out_dir="$HOME"; fi
fi
host="$(grep -Eom1 '^[a-zA-Z0-9._-]+' ansible/hosts 2>/dev/null || echo vps)"
bundle="$out_dir/recovery-bundle-${host}-$(date +%Y%m%d).tar.gz.enc"

# Stage the secret set first, because it is gathered from more than one place:
# the deploy checkout does NOT hold the restic secrets on the server.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

stage_file() {  # stage_file <src> [dest-rel]  — no-op if src missing
  local src="$1" rel="${2:-$1}"
  [[ -f "$src" ]] || return 0
  mkdir -p "$stage/$(dirname "$rel")"
  cp -a "$src" "$stage/$rel"
}

# 1) Secrets that live in the deploy/operator checkout.
stage_file ansible/hosts
stage_file .env
stage_file docker-compose.override.yml
while IFS= read -r f; do stage_file "$f"; done \
  < <(find apps -type f -name '.env' 2>/dev/null)

# 2) Backup/restic secrets. In an operator checkout they sit under backup/; on
#    the SERVER they live in /etc/restic instead (root-only). Capture from
#    wherever they actually are. The stock script only looked in backup/, so on
#    the server it silently dropped every RESTIC_PASSWORD — the safety net in
#    step 3 now makes that failure impossible to ship.
if [[ -f backup/config.env ]] || ls backup/services/*.env >/dev/null 2>&1; then
  stage_file backup/config.env
  while IFS= read -r f; do stage_file "$f"; done < <(ls backup/services/*.env 2>/dev/null || true)
elif [[ -d /etc/restic ]]; then
  # root-only; use sudo for the reads (and for the glob, which must expand as root)
  as_root() { if [[ $(id -u) -eq 0 ]]; then bash -c "$1"; else sudo bash -c "$1"; fi; }
  mkdir -p "$stage/backup/services"
  as_root 'cat /etc/restic/config.env' > "$stage/backup/config.env" 2>/dev/null || true
  as_root 'for f in /etc/restic/services/*.env; do [ -e "$f" ] && echo "$f"; done' 2>/dev/null \
    | while IFS= read -r sf; do
        as_root "cat '$sf'" > "$stage/backup/services/$(basename "$sf")" 2>/dev/null || true
      done
fi

# 3) SAFETY NET — never emit a bundle without the restic password material. That
#    is the single irreplaceable secret; a bundle missing it is worse than none
#    (false confidence). Fail loud with the fix instead.
if ! grep -rqE '^RESTIC_PASSWORD=' "$stage/backup" 2>/dev/null; then
  echo "ERROR: no RESTIC_PASSWORD captured — refusing to write an incomplete bundle." >&2
  echo "  On the server, run with sudo (restic secrets in /etc/restic are root-only):" >&2
  echo "    cd /opt/deploy && sudo scripts/make-recovery-bundle.sh" >&2
  echo "  From an operator checkout, ensure backup/config.env + backup/services/*.env exist." >&2
  exit 1
fi

# Eyeball summary — an operator can spot "5 app envs" when it should be 12.
n_app=$(find "$stage/apps" -name '.env' -type f 2>/dev/null | wc -l | tr -d ' ')
n_restic=$(grep -rlE '^RESTIC_PASSWORD=' "$stage/backup" 2>/dev/null | wc -l | tr -d ' ')
echo "Bundling $(cd "$stage" && find . -type f | wc -l | tr -d ' ') file(s) — ${n_app} app .env, ${n_restic} restic secret(s):"
(cd "$stage" && find . -type f | sort | sed 's|^\./|  |')

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo; echo "(DRY_RUN — nothing encrypted, no file written)"
  exit 0
fi

echo
echo "Choose a strong passphrase and store it WITH the bundle in a password"
echo "manager — the bundle is useless without it, and the backups without the bundle."
tar -czf - -C "$stage" . \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -out "$bundle"
chmod 600 "$bundle"
[[ -n "${SUDO_USER:-}" ]] && chown "$SUDO_USER" "$bundle" 2>/dev/null || true

echo
echo "Wrote $bundle"
echo "Store it OFFSITE (not only on this machine). Verify it decrypts:"
echo "  openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in '$bundle' | tar -tz"
