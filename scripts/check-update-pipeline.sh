#!/usr/bin/env bash
# check-update-pipeline.sh — verify the hands-off update pipeline against the
# recorded intended state (scripts/update-pipeline-state.json).
#
# The pipeline's moving parts live OUTSIDE this repo (Renovate app installs,
# Mend org settings, per-app-repo workflows), so like check-digest-freshness
# this script asserts observable reality instead: for every fleet repo it
# checks (a) a Renovate config file exists, (b) no GitHub workflow has been
# auto-disabled (schedules die silently after ~60 days of repo inactivity —
# the weekly image rebuilds' known failure mode), and (c) Renovate's
# Dependency Dashboard issue has been touched recently (the bot updates it on
# every run, making it a heartbeat for "the app is installed, enabled and not
# in Silent mode").
#
# Auth: uses `gh` — locally your login sees everything. In CI, GITHUB_TOKEN
# only reads THIS repo and public repos; private fleet repos are then
# reported as SKIP (warn), not drift. Set GH_TOKEN to a read-only
# fine-grained PAT covering the fleet to make CI authoritative.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$ROOT_DIR/scripts/update-pipeline-state.json"

read_state() { python3 -c "
import json,sys
s=json.load(open('$STATE_FILE'))
print(s['$1'])"; }

max_days="$(read_state max_days_since_renovate_activity)"
repos="$(python3 -c "
import json
s=json.load(open('$STATE_FILE'))
for r in s['app_repos']: print(r['repo'])
print(s['server_repo'])")"

drift=0
warn=0

for repo in $repos; do
  # (a) Renovate config present
  if ! gh api "repos/$repo/contents/renovate.json" --jq .name >/dev/null 2>&1 \
     && ! gh api "repos/$repo/contents/renovate.json5" --jq .name >/dev/null 2>&1; then
    if gh api "repos/$repo" --jq .name >/dev/null 2>&1; then
      echo "DRIFT  $repo: no renovate.json(5) at repo root"
      drift=1
    else
      echo "SKIP   $repo: not readable with this token (set GH_TOKEN for full coverage)"
      warn=1
      continue
    fi
  fi

  # (b) no auto-disabled workflows (60-day inactivity kill switch)
  disabled="$(gh api "repos/$repo/actions/workflows" \
    --jq '.workflows[] | select(.state != "active") | "\(.name) (\(.state))"' 2>/dev/null || true)"
  if [[ -n "$disabled" ]]; then
    echo "DRIFT  $repo: workflow not active: $disabled"
    drift=1
  fi

  # (c) Renovate heartbeat: Dependency Dashboard updated recently
  updated="$(gh api "repos/$repo/issues?creator=renovate%5Bbot%5D&state=open&per_page=10" \
    --jq '[.[] | select(.title | test("Dependency Dashboard"))][0].updated_at // empty' 2>/dev/null || true)"
  if [[ -z "$updated" ]]; then
    # Fall back to the most recent bot PR of any state.
    updated="$(gh pr list -R "$repo" --state all -L 1 \
      --search "author:app/renovate" --json createdAt \
      --jq '.[0].createdAt // empty' 2>/dev/null || true)"
  fi
  if [[ -z "$updated" ]]; then
    echo "DRIFT  $repo: no Renovate dashboard or PRs found — app not installed, repo not selected, or Silent mode"
    drift=1
  else
    age_days="$(python3 -c "
from datetime import datetime,timezone
d=datetime.fromisoformat('${updated}'.replace('Z','+00:00'))
print((datetime.now(timezone.utc)-d).days)")"
    if (( age_days > max_days )); then
      echo "DRIFT  $repo: last Renovate activity ${age_days}d ago (max ${max_days}d)"
      drift=1
    else
      echo "OK     $repo: renovate active ${age_days}d ago"
    fi
  fi
done

# Server-repo config still references the Mend-held registry secret.
if ! grep -q "secrets.GHCR_READ_TOKEN" "$ROOT_DIR/renovate.json5"; then
  echo "DRIFT  renovate.json5: ghcr.io hostRule no longer references GHCR_READ_TOKEN"
  drift=1
fi

if (( drift )); then
  echo "RESULT: drift detected — compare with scripts/update-pipeline-state.json"
  exit 1
fi
(( warn )) && echo "RESULT: ok (some repos unverifiable with this token)"
exit 0
