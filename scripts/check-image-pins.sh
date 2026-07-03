#!/usr/bin/env bash
# check-image-pins.sh — fail when any compose image is not pinned by digest.
#
# Supply-chain gate (Essential Eight patch/application control on Linux =
# image allowlisting + pinning): every `image:` in apps/*/docker-compose.yml
# and the scaffold caddy base must carry @sha256:… so a deploy pulls exactly
# the bytes that were reviewed. Renovate's pinDigests keeps pins current.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

compose_files=()
for f in apps/*/docker-compose.yml; do
  [[ -f "$f" ]] && compose_files+=("$f")
done

# The scaffold submodule may not be checked out in every CI job.
if [[ -f scaffold/docker/caddy.base.yml ]]; then
  compose_files+=("scaffold/docker/caddy.base.yml")
else
  echo "NOTE: scaffold submodule not checked out — skipping caddy.base.yml"
fi

[[ ${#compose_files[@]} -gt 0 ]] || { echo "ERROR: no compose files found" >&2; exit 1; }

fail=0
for f in "${compose_files[@]}"; do
  # image: lines that lack a @sha256: digest (comments excluded)
  while IFS= read -r line; do
    echo "ERROR: unpinned image in $f: ${line#"${line%%[![:space:]]*}"}" >&2
    fail=1
  done < <(grep -E '^\s*image:' "$f" | grep -v '#' | grep -v '@sha256:' || true)
done

if [[ $fail -ne 0 ]]; then
  echo "" >&2
  echo "Pin images as repo:tag@sha256:<digest> (docker buildx imagetools inspect <image>" >&2
  echo "prints the digest; Renovate pinDigests maintains it afterwards)." >&2
  exit 1
fi

echo "Image pin checks passed (${#compose_files[@]} compose file(s))."
