# server-[name]

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
# 1. Configure inventory and environment
cp ansible/hosts.example ansible/hosts && $EDITOR ansible/hosts
cp .env.example .env && $EDITOR .env

# 2. Install Ansible dependencies (once per machine)
ansible-galaxy collection install -r scaffold/ansible/requirements.yml

# 3. Bootstrap — run as root on first provision only
ansible-playbook -i ansible/hosts scaffold/ansible/bootstrap.yml

# 4. Harden and install Docker — idempotent, safe to re-run any time
ansible-playbook -i ansible/hosts scaffold/ansible/site.yml
```

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

To redeploy after changes:
```bash
# On the server:
cd /opt/deploy && git pull --recurse-submodules && docker compose up -d
```

---

## Add an app

Create a folder under `apps/` with three files:

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

Then add one line to the root `docker-compose.yml`:
```yaml
include:
  - apps/myapp/docker-compose.yml
```

Caddy picks up `myapp.caddy` automatically — no changes to `Caddyfile` needed.

---

## Database backups

Databases are backed up to S3-compatible storage via Restic. Each database
gets its own repository and encryption key.

**Configure:**
```bash
cp backup/config.env.example backup/config.env && $EDITOR backup/config.env

# One file per database:
cp backup/services/example.env.example backup/services/myapp.env
$EDITOR backup/services/myapp.env
```

**Deploy:**
```bash
ansible-playbook -i ansible/hosts ansible/backup.yml
```

**Adding a database** = copy `backup/services/example.env.example` to
`backup/services/newservice.env`, fill it in, re-run the playbook.

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

---

## Update the scaffold

```bash
cd scaffold && git pull origin main && cd ..
git add scaffold
git commit -m "chore: update scaffold"
git push
```

On the server: `git pull --recurse-submodules && docker compose up -d`
