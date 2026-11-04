# server-[name]

[![CI](https://github.com/uppertoe/server-instance-template/actions/workflows/ci.yml/badge.svg)](https://github.com/uppertoe/server-instance-template/actions/workflows/ci.yml)

> Replace this heading with your server name and delete this line.

VPS implementation for `[name]`. It uses [vps-base-template](https://github.com/uppertoe/vps-base-template)
for the infrastructure: Ansible provisioning and hardening, Docker, the Caddy
base configuration, the deploy wrapper and the shared CI. That scaffold is the
`scaffold/` submodule, and its `docs/` directory is the reference manual.

---

## Create a new server repo from this template

Do this once per server.

1. On GitHub, open [server-instance-template](https://github.com/uppertoe/server-instance-template)
   and choose **Use this template**, then **Create a new repository**. Name it
   `server-[name]` and keep it private.
2. Clone it with the submodule:
   ```bash
   git clone --recurse-submodules git@github.com:yourorg/server-[name].git
   cd server-[name]
   ```
   The submodule URL is `https://`, so the server can fetch the scaffold with
   a deploy key that is scoped to this repository alone.
3. Put the server name in this README, sign the commit and push. Every commit
   to this repository should be signed, because the server can be told to
   refuse an unsigned one (`deploy_verify_signature` below).

---

## Provision a new server

Everything runs from your laptop. Create the VPS (Ubuntu 24.04 LTS) and note
its address, then:

1. Add an entry for the server to `~/.ssh/config`, with `User deploy` and the
   key you want installed for the deploy account. Use the same alias in
   `ansible/hosts` and in every command below.
2. Copy and edit the inventory: `cp ansible/hosts.example ansible/hosts`.
   The example documents every variable, including alerting, log export,
   signed deploys and restricted mode.
3. Run the orchestrator:
   ```bash
   ansible-galaxy collection install -r scaffold/ansible/requirements.yml   # once per machine
   scripts/provision.sh --dry-run myserver   # preview each stage
   scripts/provision.sh myserver
   ```
   It chains bootstrap, hardening, the AWS buckets (with the `--aws-*`
   options), backups, the first deploy, alerting and the strict smoke test,
   and a re-run skips the stages that are done. It prompts for the root
   credential on the first bootstrap only. The manual step-by-step, and what
   each stage does, is `scaffold/docs/03-provisioning-a-server.md`.
4. Reboot once so the new kernel is active, then run the smoke test again:
   ```bash
   ssh myserver sudo reboot
   bash scripts/post-provision-smoke-test.sh myserver --require-backup --strict
   ```

### Secrets

Secrets never sit in plaintext in this repository and are never edited on the
server. They live under `secrets/`, encrypted with SOPS to three age keys: the
server's own key, your laptop key and an offline recovery key. The first site
play creates the server key and prints its public half. Put the three public
keys into `.sops.yaml`, then write each secret file with
`sops --input-type dotenv --output-type dotenv secrets/apps/<app>/.env.sops`
and commit it. The deploy decrypts them on the box into the `.env` files
Compose reads. `secrets/README.md` has the key steps; the design is
`scaffold/docs/13-secrets.md`.

### Restricted mode on the release tree

Once the server deploys cleanly, take the deploy account's root-equivalence
away. In restricted mode the deploy account has wrapper-only sudo and no
docker group, root fetches and verifies each commit itself, and every deploy
is exported into a root-owned release under `/opt/deploy-releases`, with
`/opt/deploy` a link to the current one. The runbook is
`scaffold/docs/05-access-model.md`; the release tree is
`scaffold/docs/15-release-tree.md`. In short:

1. Verify the `admin` break-glass account first:
   `ssh admin@<host> 'sudo -n true && docker ps >/dev/null && echo ADMIN-OK'`.
2. Set `deploy_restricted_mode=true`, `deploy_release_tree=true`,
   `deploy_verify_signature=true` (with `deploy_allowed_signers`) and
   `deploy_repo_url` as host variables, and switch `ansible_user=admin`.
3. Re-run `ansible-playbook -i ansible/hosts scaffold/ansible/site-quick.yml`.
4. Run the smoke test through an alias that connects as `admin`; it detects
   the mode from the user it connects as.

---

## Deploy apps to the server

`scripts/provision.sh` clones this repository to `/opt/deploy` on the server
and runs the first deploy. The server needs a read-only deploy key for this
repository: create one on the server (`ssh-keygen -t ed25519 -f
~/.ssh/github-deploy`), add its public half under the repository's
**Settings, Deploy keys** without write access, and point `~/.ssh/config` on
the server at it for `github.com`. The release tree copies that key to root.

To deploy after a change, push to `main` and run:

```bash
ssh myserver ./deploy
```

With `deploy_auto_update=true` in the inventory, the server applies each
merged commit itself and announces the result over ntfy. Either way the
wrapper verifies the signature on the commit, renders the secrets, pulls the
images, runs each executable `apps/*/deploy.sh` hook, and then runs
`docker compose up -d --remove-orphans --wait`, recreating only the services
whose settings or mounted files changed.

---

## Add an app

Create a folder under `apps/` with three files. The web-facing service must be
named after the folder, and network wiring is generated, so add none:

```text
apps/
  myapp/
    docker-compose.yml
    .env.example
    myapp.caddy
    deploy.sh        # optional release hook (migrations and the like)
```

`apps/myapp/docker-compose.yml` pins its image by digest and carries the CIS
Docker §5 hardening block: a uid of its own (never 1000, the deploy
account), `cap_drop: [ALL]`, `no-new-privileges`, `read_only` with `tmpfs`,
`mem_limit`, `pids_limit`, a `healthcheck`, and `cgroup_parent:
vps-noswap.slice` for a service a visitor waits on. Copy the block from
`apps/auth/docker-compose.yml`; the rules and their reasons are in
`scaffold/docs/04-server-repo.md`. A control a container cannot meet is
recorded, with its reason, in `ansible/audit-exceptions.yml`.

`apps/myapp/.env.example` lists every variable the app reads, with no values.
The real values go into `secrets/apps/myapp/.env.sops`.

`apps/myapp/myapp.caddy` declares who may reach the site. A gated app imports
one guard, which runs the login wall and proxies to the upstream itself:

```caddyfile
myapp.{$DOMAIN} {
	import protected myapp:3000
}
```

A site that must stay public carries a marker saying why, and strips the
gateway cookie and any client-sent identity headers before the app sees them:

```caddyfile
# scaffold-lint: public -- the app enforces its own token auth
myapp.{$DOMAIN} {
	reverse_proxy myapp:3000 {
		import strip_public
	}
}
```

The renderer refuses a site with neither a guard nor a marker, and refuses a
bare `reverse_proxy` line. The guard catalogue is at the top of
`apps/auth/auth.caddy`, and `scaffold/docs/07-auth.md` explains the model.
Keep `.caddy` comments free of braces.

If the app needs a release hook, make it executable in git
(`git add --chmod=+x apps/myapp/deploy.sh`). Hooks run as root from the
release, so read `.env` files as data and never `source` them.

Then add one line to the root `docker-compose.yml`:

```yaml
include:
  - apps/myapp/docker-compose.yml
```

and re-render the committed Caddy bundle:

```bash
bash scaffold/docker/render-caddy-routes.sh
git add .generated
```

`.generated/caddy/` is generated but committed, like a lockfile. `apps.caddy`
carries every app's routes and is the only file Caddy mounts, `networks.yml`
gives each app a private proxy network that only Caddy shares, and the two
`.tsv` files tell the gateway which groups each route needs. CI fails if the
bundle drifts from its sources.

---

## Authentication

This repo ships an optional passwordless login wall (`apps/auth/`) powered by
[vps-scaffold-auth](https://github.com/uppertoe/vps-scaffold-auth). Users sign in
with an emailed code; apps behind it receive `Remote-User`, `Remote-Email` and
`Remote-Groups` headers, and nothing else can set those headers. It is off by
default.

To enable it, write `secrets/apps/auth/.env.sops` from `apps/auth/.env.example`
(at least `SESSION_SECRET`, `ALLOWED_EMAIL_DOMAINS`, `ADMIN_EMAILS` and the
`EMAIL_*` settings), uncomment the `apps/auth` include in `docker-compose.yml`,
point `auth.<your-domain>` at the server and deploy. Guard an app with
`import protected <upstream>` as shown above. The admin TOTP option, the
break-glass cards and a local end-to-end test are in
[scaffold/docs/07-auth.md](https://github.com/uppertoe/vps-base-template/blob/main/docs/07-auth.md).

### CMS commit broker (cms-auth), optional

`apps/cms-auth` ships off by default. It lets [Decap CMS](https://decapcms.org/)
editors who have no GitHub accounts commit through one shared GitHub App, with
each commit authored as the signed-in editor. Editors sign in through the
gateway above and must hold the `cms-editors` group.

Enable the gateway first, then run `bash apps/cms-auth/setup.sh` on your
laptop. It walks through creating the GitHub App, writes the two env files
and prints the `sops` commands that move them into `secrets/`. Rename
`cms-auth.caddy.disabled` to `cms-auth.caddy`, uncomment its include, and
point the CMS site's Decap `config.yml` at `https://cms-auth.<domain>/api`.
See [`apps/cms-auth/README.md`](apps/cms-auth/README.md).

---

## Backups

Databases are backed up to S3-compatible storage with restic, one repository
and key per database, hourly by default, with a weekly repository check and a
monthly restore drill. `scripts/aws-backup-setup.py` creates the bucket and a
prefix-scoped IAM user and prints the values to use.

The restic configuration lives in `secrets/backup/`: `config.env.sops` holds
the shared credentials and retention (from `backup/config.env.example`) and
`services/<name>.env.sops` holds one database each (from
`backup/services/service.env.example`). The deploy installs them into
`/etc/restic`, so a database is backed up for exactly as long as its file is
in the repository. `ansible/backup.yml` installs the restic timers:

```bash
ansible-playbook -i ansible/hosts ansible/backup.yml
bash scripts/post-provision-smoke-test.sh myserver --require-backup
```

The `KEEP_*` values set how many snapshots restic keeps; the schedule is the
Ansible variable `backup_schedule`. The `env-files` service in
`backup/services/env-files.env.example` is for a server that has not adopted
SOPS, whose `.env` files exist only on the box.

### Recovery set

Rebuilding the box needs the files that are deliberately not in git in plain
form. With secrets in SOPS, this repository and the recovery key in your
password manager are the recovery set: the env files are under `secrets/`,
the restic configuration under `secrets/backup/`, and the inventory in
`secrets/recovery.sops`. The strict smoke test reports the set as held in
SOPS. The rebuild drill is `scaffold/docs/09-recovery.md`.

A server without SOPS packages the same set into one encrypted bundle instead.
That script must run on the server with `sudo`, because the restic secrets in
`/etc/restic` are root-only and a laptop bundle silently omits them:

```bash
ssh -t myserver 'cd /opt/deploy && sudo scripts/make-recovery-bundle.sh'
scp myserver:'~/recovery-bundle-*.tar.gz.enc' .
```

### Off-host log export

The scaffold's `log-export` role ships nightly, hash-chained log archives to an
S3 bucket that even the server's own credentials cannot rewrite (Object Lock
and a write-only IAM user). `scripts/aws-logs-setup.py` creates that bucket
and prints the `log_export_*` values for `ansible/hosts`; re-run
`site-quick.yml` afterwards.

### Cloud-side review (Prowler)

The S3 and IAM posture lives in AWS, outside what the VPS audits can see.
Review it quarterly from your laptop with
[Prowler](https://github.com/prowler-cloud/prowler), scoped to `s3 iam`, and
file the report with the audit pack. It is not run from CI because it needs
your admin credentials.

### Keeping images current

Every compose image is pinned by digest, and CI's `static-checks` job refuses
an unpinned one. Two things keep the pins current. The weekly **Digest
Freshness** workflow compares each pin with the registry and opens an issue on
drift (`bash scripts/check-digest-freshness.sh` runs the same check locally).
A self-hosted Renovate runner, driven by a fleet GitHub App, opens the bump
PRs: third-party digest bumps and scaffold bumps automerge once CI is green,
version bumps of images wait for a person. The committed `renovate.json5` is
configured for that runner, and its `postUpgradeTasks` entry (which only a
self-hosted Renovate executes) rewrites the shared files on a scaffold bump.
The Mend-hosted app is not used. `scripts/update-pipeline-state.json` records
the runner, the app and your app repositories, and the weekly
**Update Pipeline Freshness** workflow checks reality against it.

---

## Local development

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
docker compose up -d
docker compose exec caddy caddy trust   # once per machine
```

---

## Security auditing

**Compliance pack:** the evidence templates (SSP, asset register, scope
determination, jurisdiction record, retention design, IR runbook, control
matrix) are the scaffold's one set, `scaffold/docs/templates/`. Copy them to
`compliance/`, answer the scope determination first, then fill the
`⟨fill at commissioning⟩` fields. A private server repo tracks the filled pack
(remove the `compliance/` rule from `.gitignore` there).

**Shared tooling:** the checks under `scripts/` are shims for the scaffold's
copies, and the CI workflows call the scaffold's reusable workflows at the
submodule commit. `bash scripts/check-server-files.sh` keeps both in step and
`.scaffold-server.yml` holds this server's choices. See
[scaffold/docs/14-server-tooling.md](https://github.com/uppertoe/vps-base-template/blob/main/docs/14-server-tooling.md).

Run the audits against the real server. `audit-all.yml` is the one-command
evidence bundle; it needs the deployment's exception register:

```bash
ansible-playbook -i ansible/hosts scaffold/ansible/audit-all.yml \
  -e @ansible/audit-exceptions.yml
```

Reports land in `reports/` (gitignored). Individually: `audit-openscap.yml`
(CIS OS), `audit-docker.yml` (CIS Docker §1 to §4), `audit-compose.yml`
(CIS Docker §5 on the running stack), `audit-lynis.yml` and `audit-vuln.yml`
(Trivy). Fix host findings in inventory variables or the scaffold's roles,
and container findings in `apps/*/docker-compose.yml`; a finding that is
accepted goes into `ansible/audit-exceptions.yml` with its reason. See
`scaffold/docs/06-auditing.md`.

---

## Update the scaffold

Renovate opens a PR for each new scaffold commit and runs the fix step in the
branch. To bump by hand:

```bash
git -C scaffold fetch && git -C scaffold checkout <commit>
bash scaffold/scripts/server/check-server-files.sh --fix   # the shims and workflows may be new
bash scaffold/docker/render-caddy-routes.sh                # the renderer may have changed
git add scaffold scripts .github .gitignore .generated && git commit
```

Read every `scaffold/UPGRADING.md` entry newer than your old pointer before
re-running the site play; some bumps need an operator action.
