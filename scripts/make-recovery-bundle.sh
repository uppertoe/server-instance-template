#!/usr/bin/env bash
# make-recovery-bundle.sh — collect everything NOT in git that a rebuild needs,
# into one encrypted file you store offsite.
#
# The repo rebuilds the box only together with these secrets: the inventory,
# the server/app .env files, and the backup credentials (including the restic
# repository password — without it the backups are undecryptable noise). If
# they exist only on one laptop, that laptop is part of your recovery path.
#
# Usage:  bash scripts/make-recovery-bundle.sh [output-dir]
# Restore: openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
#            -in <bundle> | tar -xzv
#
# Store the bundle somewhere that survives the laptop (cloud drive, second
# machine); store the passphrase in a password manager. Re-run after rotating
# any credential. See scaffold/docs/09-recovery.md for the full drill.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Default OUTSIDE the worktree — a bundle written into the repo is one
# `git add -f` from a catastrophic leak. Pass an explicit dir to override.
out_dir="${1:-$HOME}"
stamp="$(date +%Y%m%d)"
host="$(grep -Eom1 '^[a-zA-Z0-9._-]+' ansible/hosts 2>/dev/null || echo vps)"
bundle="$out_dir/recovery-bundle-${host}-${stamp}.tar.gz.enc"

# Candidate secret files (all gitignored); include only those that exist.
candidates=(
  ansible/hosts
  .env
  docker-compose.override.yml
  backup/config.env
)
# apps/**/.env (nested) + backup service envs — match what .gitignore hides so
# a secret the gitignore protects can never be missed by the bundle.
while IFS= read -r f; do candidates+=("$f"); done \
  < <(find apps -type f -name '.env' 2>/dev/null; ls backup/services/*.env 2>/dev/null || true)

files=()
for f in "${candidates[@]}"; do
  [[ -f "$f" ]] && files+=("$f")
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "ERROR: no secret files found (ansible/hosts, .env, apps/*/.env, backup/*.env)." >&2
  echo "Run this from a working checkout that has the live configuration." >&2
  exit 1
fi

echo "Bundling ${#files[@]} file(s):"
printf '  %s\n' "${files[@]}"
echo
echo "Choose a strong passphrase and store it in a password manager —"
echo "the bundle is useless without it, and so are your backups without the bundle."

tar -czf - "${files[@]}" \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -out "$bundle"
chmod 600 "$bundle"

echo
echo "Wrote $bundle"
echo "Store it OFFSITE (not only on this machine). Verify it decrypts:"
echo "  openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in '$bundle' | tar -tz"
