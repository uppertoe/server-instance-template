# CLAUDE.md

Guidance for working in a **server repo** (one git repo per VPS), created from
`server-instance-template`. Each repo provisions and runs a single small (~2 GB)
Ubuntu VPS: a hardened host running Docker + a Caddy reverse proxy that fronts a
handful of web-app containers.

## Architecture (read this first)

- **`scaffold/` is a git submodule** of `vps-base-template` — the shared scaffold:
  Ansible hardening roles, the base Caddy service, audit playbooks, and all the
  detailed docs. **Never edit files under `scaffold/` from this repo** — changes
  are lost on the next submodule update. To change hardening / the Caddy base /
  docs: edit them in the **`vps-base-template`** repo, push, then bump the pointer
  here (`git -C scaffold checkout <commit> && git add scaffold && git commit`).
- **`docker-compose.yml`** uses Compose `include:` to assemble
  `scaffold/docker/caddy.base.yml` + `.generated/caddy/networks.yml` + each
  app's compose into one stack.
- **`apps/<name>/`** is one app: `docker-compose.yml`, `.env.example`, `<name>.caddy`.
  The web-facing service must be named after the folder (`apps/ntfy/` → `ntfy`).
- **`.generated/caddy/` is generated-but-committed** (like a lockfile) by
  `bash scaffold/docker/render-caddy-routes.sh`: `apps.caddy` bundles every
  `apps/*/*.caddy` route (mounted into Caddy — the container never mounts the
  repo, keeping secrets off the proxy) and `networks.yml` wires one private
  proxy network per app. Re-render + commit after any app change; CI fails on
  drift. Never edit these files by hand.
- **`Caddyfile`** is intentionally near-empty — routes live in the app snippets
  and the rendered bundle. Don't add routes here.
- **The detailed docs live in `scaffold/docs/01`–`11`.** Prefer pointing the user
  there over re-explaining. Most relevant: `04-server-repo.md` (adding apps),
  `06-auditing.md` (audits), `07-auth.md` (login wall), `08-security-model.md`
  (which benchmark governs each layer + the accepted-exceptions register),
  `09-recovery.md` (recovery bundle + rebuild drill), `10-lts-migration.md`
  (OS release jumps), `11-incident-response.md` (containment → notification →
  rebuild).
- **`docs/compliance-pack/`** is the filled Vic-health evidence pack for the
  staging instance (worked example of `scaffold/docs/templates/`). Real
  deployments re-answer `scope-determination.md` first, then re-fill the
  `⟨fill at commissioning⟩` fields. Tripwire running through it: the first
  app holding identifiable health information forces AU hosting,
  health-service commissioning, TOTP, and at-rest encryption.

## Lifecycle / commands

Inventory lives in `ansible/hosts` (gitignored; copy `ansible/hosts.example`).
`.env` holds `DOMAIN` (gitignored). All playbooks are run from `scaffold/ansible/`.

- **Provision a fresh VPS:** `bootstrap.yml` (once, as root, `--ask-pass`) →
  `site-first-run.yml` (hardening + Docker, as the `deploy` user). See README §"Provision".
- **Day-to-day host re-apply:** `site-quick.yml` (fast path, skips slow compliance steps).
- **Deploy apps:** on the server, `/opt/deploy` is a clone of this repo; run
  `ssh <host> ./deploy` (git pull --recurse-submodules → `docker compose pull` →
  enforce `.env` perms to 600 → run each executable `apps/*/deploy.sh` hook
  (migrations etc.) → `docker compose up -d --remove-orphans --wait`).
- **Access model:** `deploy_restricted_mode` (host var) narrows deploy to
  wrapper-only sudo (no docker group); site plays then run as `admin`
  (`ansible_user=admin`) and `./deploy` delegates to `sudo vps-deploy`. See
  `scaffold/docs/05-access-model.md` for the migration runbook. The smoke test
  is mode-aware (connect as deploy = default mode, admin = restricted).
- **Audit (run against the real VPS):** `scaffold/ansible/audit-all.yml` is the
  one-command evidence bundle (host captures + all audits, control-tagged
  INDEX). Individually: `audit-openscap.yml` (CIS OS, tailored),
  `audit-docker.yml` (CIS Docker §1–4), `audit-compose.yml` (CIS Docker §5 +
  DB tier separation), `audit-lynis.yml`, `audit-vuln.yml` (Trivy CVEs).
  One-time AWS setup helpers (run locally): `scripts/aws-backup-setup.py`,
  `scripts/aws-logs-setup.py` (Object-Locked log bucket + write-only IAM user).
- **Local dev:** `cp docker-compose.override.yml.example docker-compose.override.yml`,
  `docker compose up -d`, then `docker compose exec caddy caddy trust` once.

## Rules & conventions (the easy-to-get-wrong parts)

- **Every app container must carry the CIS Docker §5 block:** non-root `user:`,
  `cap_drop: [ALL]` (+ minimal `cap_add`), `security_opt: [no-new-privileges:true]`,
  `read_only: true` + `tmpfs`/named volumes, `mem_limit`, `pids_limit`, `healthcheck`.
  Copy the pattern from `apps/auth/` or `docker/caddy.base.yml`. `audit-compose.yml`
  and CI (`forward-auth-security`, `compose-smoke`, `container-security`) enforce it.
- **Every image is pinned by digest** (`image: repo:tag@sha256:…`) — including the
  bundled `apps/auth` and `apps/ntfy`. CI's `image-pins` job
  (`scripts/check-image-pins.sh`) fails on any unpinned image; Renovate
  (`renovate.json`, `pinDigests`) keeps the digests current via PR.
- **`.caddy` snippets: never put `{` or `}` in a comment** — the route renderer
  counts braces when assembling the Caddyfile bundle and unbalanced ones corrupt it.
- **Protect an app/path with auth:** the guard snippets take the upstream as an
  argument and reverse_proxy it themselves — `import protected app:3000` (whole
  site) or `handle /admin/* { import protected app:3000 }` (one path). See
  `scaffold/docs/07-auth.md` and the snippet catalogue in `apps/auth/auth.caddy`.
  `forward_auth` strips client-supplied `Remote-User` / `Remote-Email` /
  `Remote-Groups` and injects the auth service's — apps trust only those three
  headers and publish **no** host ports.
- **Auth is off by default:** the `apps/auth` include in `docker-compose.yml` is
  commented; enabling needs `apps/auth/.env`. Protected routes `502` until it's on.
- **Secrets:** per-app `.env` files (gitignored, set to mode 600 on the server by
  `./deploy`). Never commit a real `.env`; always keep an `.env.example`.
- **Caddy is the only thing that publishes ports** (80/443). Each app gets its
  own generated proxy network (`<name>_proxy`) that only Caddy shares — never
  hand-wire proxy networks in app compose files, and never put two apps on one
  network (`audit-compose.yml` fails if they share a Caddy-reachable network).
  Private backend networks (app ↔ its own db) are still defined in the app file.
- **`scripts/check-template-consistency.sh`** asserts required files exist — run it
  after adding/removing app scaffolding.

## When making changes

- Adding an app: create `apps/<name>/{docker-compose.yml,.env.example,<name>.caddy}`
  (with the §5 block + an `import protected` if it should require login), add
  one `include:` line to `docker-compose.yml`, then re-render the bundle:
  `bash scaffold/docker/render-caddy-routes.sh && git add .generated`.
  See `scaffold/docs/04-server-repo.md`.
- Host hardening / benchmark / audit changes belong in **`vps-base-template`**, not
  here — then bump the `scaffold` submodule.
- Keep CI green: `compose-smoke`, `forward-auth-security`, `container-security`,
  `template-consistency`.
- Commit/push only when asked; this repo's default branch is `main`.
