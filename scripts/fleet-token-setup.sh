#!/usr/bin/env bash
# fleet-token-setup.sh — provision the FLEET_READ_TOKEN_* Actions secrets that
# make the weekly update-pipeline-freshness check authoritative over PRIVATE
# fleet repos (without them, CI reports those repos as SKIP, not verified).
#
# A GitHub fine-grained PAT is bound to ONE resource owner (user or org), and
# the fleet spans more than one — so each owner holding private fleet repos
# gets its own READ-ONLY token, stored on the server repo as
# FLEET_READ_TOKEN_<OWNER> ('-' -> '_', uppercased).
# check-update-pipeline.sh picks the matching one per repo.
#
# Mint each token at https://github.com/settings/personal-access-tokens/new
#   Resource owner:         the owner this script names
#   Expiration:             up to you (note it in update-pipeline-state.json)
#   Repository access:      "Only select repositories" -> the private fleet
#                           repos this script lists for that owner
#   Repository permissions: Contents, Issues, Pull requests, Actions —
#                           all "Read-only" (Metadata is added automatically)
#
# Usage:
#   bash scripts/fleet-token-setup.sh                    # hidden prompt per owner
#   bash scripts/fleet-token-setup.sh --from-file <owner>=<path> [--from-file ...]
#
# Tokens are validated against every private fleet repo of their owner
# (exactly the API calls the weekly check makes) before being stored, and are
# never echoed or written anywhere except the GitHub secret.
#
# Requires: gh authenticated as you (reads repo visibility, writes secrets),
# python3.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$ROOT_DIR/scripts/update-pipeline-state.json"

# owner=path pairs from --from-file (plain array: macOS ships bash 3.2).
token_files=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-file)
      [[ "${2:-}" == *=* ]] || { echo "usage: --from-file <owner>=<path>" >&2; exit 2; }
      token_files+=("$2"); shift 2 ;;
    *) echo "unknown argument: $1 (only --from-file <owner>=<path> is accepted)" >&2; exit 2 ;;
  esac
done

server_repo="$(python3 -c "
import json
print(json.load(open('$STATE_FILE'))['server_repo'])")"
repos="$(python3 -c "
import json
for r in json.load(open('$STATE_FILE'))['app_repos']: print(r['repo'])")"

# The private fleet repos, grouped by owner. The server repo itself is
# excluded: the workflow's own GITHUB_TOKEN reads it natively.
private_repos=""
for repo in $repos; do
  vis="$(gh api "repos/$repo" --jq .visibility)"
  [[ "$vis" == "private" ]] && private_repos="$private_repos $repo"
done

if [[ -z "$private_repos" ]]; then
  echo "No private fleet repos in $STATE_FILE — nothing to provision."
  exit 0
fi

owners="$(printf '%s\n' $private_repos | cut -d/ -f1 | sort -u)"
echo "Private fleet repos needing a read-only token, by owner:"
for owner in $owners; do
  echo "  $owner:$(printf '%s\n' $private_repos | grep "^$owner/" | sed "s|^$owner/| |" | tr -d '\n')"
done
echo

fail=0
for owner in $owners; do
  secret_name="FLEET_READ_TOKEN_$(printf '%s' "$owner" | tr '[:lower:]-' '[:upper:]_' | tr -cd 'A-Z0-9_')"
  owner_repos="$(printf '%s\n' $private_repos | grep "^$owner/")"

  # Fetch the token: --from-file wins, else hidden prompt.
  tok=""
  for pair in ${token_files[@]+"${token_files[@]}"}; do
    if [[ "${pair%%=*}" == "$owner" ]]; then
      tok="$(tr -d '[:space:]' < "${pair#*=}")"
    fi
  done
  if [[ -z "$tok" ]]; then
    printf 'Fine-grained PAT for resource owner %s (input hidden): ' "$owner"
    read -rs tok; echo
  fi
  if [[ -z "$tok" ]]; then
    echo "SKIP   $owner: no token given"
    fail=1
    continue
  fi

  # Validate: exactly the calls check-update-pipeline.sh makes.
  ok=1
  for repo in $owner_repos; do
    for probe in "repos/$repo" "repos/$repo/actions/workflows" \
                 "repos/$repo/issues?per_page=1" "repos/$repo/pulls?state=all&per_page=1"; do
      if ! GH_TOKEN="$tok" gh api "$probe" >/dev/null 2>&1; then
        echo "FAIL   $owner: token cannot read $probe"
        echo "       (check Repository access includes $repo and Contents/Issues/PRs/Actions are read-enabled)"
        ok=0
      fi
    done
  done
  if [[ "$ok" -ne 1 ]]; then
    fail=1
    continue
  fi

  printf '%s' "$tok" | gh secret set "$secret_name" -R "$server_repo"
  echo "OK     $owner: validated against$(printf ' %s' $owner_repos) -> secret $secret_name set on $server_repo"
done

if [[ "$fail" -ne 0 ]]; then
  echo "RESULT: incomplete — re-run for the owners marked FAIL/SKIP"
  exit 1
fi
echo "RESULT: done. Verify end-to-end with:"
echo "  gh workflow run update-pipeline-freshness.yml -R $server_repo   # then watch the run"
