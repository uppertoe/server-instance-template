# server-[name]

[![CI](https://github.com/uppertoe/server-instance-template/actions/workflows/ci.yml/badge.svg)](https://github.com/uppertoe/server-instance-template/actions/workflows/ci.yml)

> Replace this heading with your server name and delete this line.

VPS implementation for `[name]`. Uses [vps-base-template](https://github.com/uppertoe/vps-base-template)
for infrastructure — Ansible provisioning, hardening, Docker setup, and Caddy base config.

---

## Create a new server repo from this template

Do this once per server.

1. On GitHub, open [server-instance-template](https://github.com/uppertoe/server-instance-template)
   and click **Use this template → Create a new repository**.
2. Name it `server-[name]` (e.g. `server-mycompany`). Keep it **private**.
3. Clone it locally — the `scaffold` submodule is included automatically:
   ```bash
   git clone --recurse-submodules git@github.com:yourorg/server-[name].git
   cd server-[name]
   ```
4. Edit the repo name in this README, then commit:
   ```bash
   git add README.md && git commit -m "chore: name server repo"
   git push
   ```

That's it — your server repo is ready. Continue below to provision the server.

---

## Provision a new server

Run these **from your local machine** — Ansible SSHs into the VPS on your behalf.

```bash
# 1. Add the server to your local SSH config (~/.ssh/config)
#    Replace "myserver" with your own alias.
#    Use that same alias in ~/.ssh/config, ansible/hosts, and the smoke test.
cat >> ~/.ssh/config <<'EOF'

Host myserver
    HostName YOUR_SERVER_IP
    User deploy
    # Use whichever SSH key you want bootstrap to install for deploy.
    IdentityFile ~/.ssh/id_ed25519
EOF

# 2. Configure inventory and environment
#    Replace "myserver" in ansible/hosts too.
#    Keep ansible_ssh_private_key_file aligned with the same key.
#    Bootstrap will install the matching .pub onto the server.
cp ansible/hosts.example ansible/hosts && $EDITOR ansible/hosts
cp .env.example .env && $EDITOR .env

# 3. Install Ansible dependencies (once per machine)
ansible-galaxy collection install -r scaffold/ansible/requirements.yml

# 4. Bootstrap — run once as root on a fresh VPS
#    Most providers give you a root password — --ask-pass makes Ansible prompt for it.
#    If your provider gave you a root SSH key instead, omit --ask-pass.
ansible-playbook -i ansible/hosts scaffold/ansible/bootstrap.yml --ask-pass

# 5. First-run hardening and Docker install
#    From here on Ansible uses the deploy user with your SSH key (no password needed).
#    This heavier pass enables the slower maintenance/compliance steps too.
ansible-playbook -i ansible/hosts scaffold/ansible/site-first-run.yml

# 6. Quick day-to-day re-apply path for later changes
ansible-playbook -i ansible/hosts scaffold/ansible/site-quick.yml

# 7. Reboot once so the latest kernel and package updates are active
ssh myserver sudo reboot

# Wait a minute or two for SSH to return, then rerun the smoke test.

# 8. Smoke test the fresh VPS
bash scripts/post-provision-smoke-test.sh myserver
```

Mode summary:
- `scaffold/ansible/site-first-run.yml`: heavier first-run/compliance pass
- `scaffold/ansible/site-quick.yml`: fast day-to-day apply path

This smoke test checks SSH access, sudo, Docker, systemd services, SSH hardening,
UFW rules, root-account lock state, and deploy-user setup against the real VPS.

`myserver` is only an example alias. Rename it to whatever you want, but keep it
consistent across `~/.ssh/config`, `ansible/hosts`, and any `ssh` or smoke-test
commands you run.

---

## Deploy apps to the server

Once provisioned, clone the repo **on the server** so Docker Compose can read it:

```bash
# SSH into the server first, then:
git clone --recurse-submodules git@github.com:yourorg/server-[name].git /opt/deploy
cd /opt/deploy
cp .env.example .env && $EDITOR .env
# Create .env for each app too (see apps/*/env.example)
docker compose up -d
```

For runtime secrets, edit the files on the server in `/opt/deploy`:
- `.env`
- `apps/*/.env`

Docker Compose reads those files directly from the server checkout, so local
copies on your laptop do not affect the running apps until you update the repo
on the VPS.

To redeploy after changes:
```bash
ssh myserver ./deploy
```

The deploy helper also normalizes secret-file permissions on each run:
- `.env`
- `apps/*/.env`
- `backup/config.env`
- `backup/services/*.env`

Those files are set to mode `600` before Compose restarts containers.

Deploy order:
- `git pull --recurse-submodules`
- `docker compose pull`
- run each executable `apps/*/deploy.sh` hook, if present
- `docker compose up -d --remove-orphans`

That gives each app a repo-local release hook without hard-coding app-specific
steps into the shared `~/deploy` helper.

---

## Add an app

Typical app layout:

```text
apps/
  myapp/
    docker-compose.yml
    .env.example
    myapp.caddy
    deploy.sh        # optional
```

Create a folder under `apps/` with these files:

**`apps/myapp/docker-compose.yml`**
```yaml
services:
  myapp:
    image: yourorg/myapp:latest
    restart: unless-stopped
    env_file: apps/myapp/.env
    networks:
      - caddy

networks:
  caddy:
    external: true
    name: caddy
```

**`apps/myapp/.env.example`** — list every required variable (no values)

**`apps/myapp/myapp.caddy`**
```
myapp.{$DOMAIN} {
    reverse_proxy myapp:3000
}
```

Optional: add an executable **`apps/myapp/deploy.sh`** if the app needs release
steps before the final `docker compose up -d --remove-orphans`.

Make the hook executable in git so it stays executable on the server after
pulls:
```bash
chmod +x apps/myapp/deploy.sh
git add --chmod=+x apps/myapp/deploy.sh
```

Example for Django:
```bash
#!/usr/bin/env bash
set -euo pipefail

docker compose run --rm myapp_django python manage.py migrate
docker compose run --rm myapp_django python manage.py collectstatic --noinput
```

Then add one line to the root `docker-compose.yml`:
```yaml
include:
  - apps/myapp/docker-compose.yml
```

Caddy picks up `myapp.caddy` automatically — no changes to `Caddyfile` needed.

Permission model:
- Commit `.env.example` files to git as normal templates.
- Do not commit real `.env` files.
- Let `~/deploy` reset real `.env` files on the server to mode `600` each run.
- Let git carry the executable bit for `apps/*/deploy.sh`.

---

## Database backups

Databases are backed up to S3-compatible storage via Restic. Each database
gets its own repository and encryption key. Backups run hourly by default, and
repository verification runs weekly by default on an explicit off-hour schedule.

**Configure:**
```bash
cp backup/config.env.example backup/config.env && $EDITOR backup/config.env

# One file per database:
cp backup/services/service.env.example backup/services/myapp.env
$EDITOR backup/services/myapp.env
```

If you use AWS for backup storage, you can provision the bucket + IAM user
locally on your laptop first:
```bash
pip install boto3
python3 scripts/aws-backup-setup.py \
  --profile my-aws-admin \
  --bucket myserver-backups \
  --iam-user myserver-backup
```

That helper is idempotent. It prints the AWS values to copy into
`backup/config.env`, and can optionally update that file locally with
`--write-config`.

It also scopes the backup IAM user to the bucket's `backups/` prefix, so
service repositories should use paths like
`s3:s3.amazonaws.com/<bucket>/backups/<service>`.

`backup/config.env` controls shared credentials and snapshot retention only.
The `KEEP_DAILY`, `KEEP_WEEKLY`, and `KEEP_MONTHLY` values tell Restic how many
snapshots to retain after each run; they do not change the schedule. The
backup job schedule is controlled by the Ansible variable `backup_schedule`,
which defaults to `hourly`.

Unlike the app/runtime `.env` files above, these backup env files are edited
locally in your server repo on your laptop. The backup playbook uploads them to
the server and installs them into `/etc/restic/`.

**Deploy:**
```bash
ansible-playbook -i ansible/hosts ansible/backup.yml

# Then rerun the smoke test in strict backup mode:
bash scripts/post-provision-smoke-test.sh myserver --require-backup
```

**Adding a database** = copy `backup/services/service.env.example` to
`backup/services/newservice.env`, fill it in, re-run the playbook.

For `CONTAINER_NAME`, you can use either the exact running container name or
the Compose service/container stem if it is unique. For example, `jw_postgres`
will resolve to a container such as `deploy-jw_postgres-1`.

**Restore:**
```bash
# On the server:
/opt/backup/restore.sh --service myapp --list
/opt/backup/restore.sh --service myapp --target myapp_test   # safe test restore
/opt/backup/restore.sh --service myapp                       # production restore (prompts)
```

**Trigger a backup now:**
```bash
ssh myserver sudo systemctl start backup.service
ssh myserver journalctl -u backup.service -f

# Manual repository verification:
ssh myserver sudo systemctl start backup-verify.service
ssh myserver journalctl -u backup-verify.service -f
```

**Local backup tests before deploying to a real VPS:**
```bash
cd scaffold
molecule test -s backup
bash backup/tests/integration/run_tests.sh
cd ..
```

---

## Local development

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
docker compose up -d
docker compose exec caddy caddy trust   # once per machine — adds CA to keychain
```

---

## Security auditing

Run against a real provisioned VPS (not locally):

```bash
ansible-playbook -i ansible/hosts scaffold/ansible/audit-lynis.yml
ansible-playbook -i ansible/hosts scaffold/ansible/audit-openscap.yml
ansible-playbook -i ansible/hosts scaffold/ansible/audit-docker.yml
```

Reports saved to `reports/` (gitignored).

Feedback loop:
1. Run `scaffold/ansible/site-first-run.yml` to establish the strongest baseline the scaffold supports by default.
2. Run `scaffold/ansible/audit-openscap.yml` and `scaffold/ansible/audit-docker.yml`.
3. Review the reports and separate findings into:
   expected platform exceptions, host-hardening gaps, and per-container app gaps.
4. Fix host gaps in inventory vars or scaffold roles, and fix container gaps in `apps/*/docker-compose.yml`.
5. Re-run `scaffold/ansible/site-quick.yml`.
6. Re-run the audits until the remaining findings are either resolved or formally accepted.

---

## Update the scaffold

```bash
# Existing server repos do not automatically pick up new scaffold commits.
# Update the submodule, then commit the new scaffold pointer in your repo.
git submodule update --remote --merge scaffold
git add scaffold
git commit -m "chore: update scaffold"
git push
```

If a template fix touched top-level files such as `Caddyfile`, `Caddyfile.local`,
or `ansible/hosts.example`, copy those changes into your existing server repo
manually too. Top-level files are copied when the repo is created; only
`scaffold/` stays linked as a submodule.

On the server: `~/deploy`
