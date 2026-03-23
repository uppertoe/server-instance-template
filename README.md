# server-[name]

> **Before pushing either repo to GitHub:**
> Update `.gitmodules` with the real URL of your `vps-scaffold` repo:
> ```
> [submodule "scaffold"]
>     path = scaffold
>     url = git@github.com:yourorg/vps-scaffold.git
> ```
> Then `git submodule sync && git add .gitmodules && git commit -m "chore: update scaffold remote"`
>
> Delete this block once done.

> Replace this heading and delete this line once you've created your server repo.

VPS implementation for `[name]`. Uses [vps-scaffold](https://github.com/yourorg/vps-scaffold)
for infrastructure — Ansible provisioning, hardening, Docker setup, and Caddy base config.

## First-time setup

```bash
# 1. Clone (submodules included)
git clone --recurse-submodules git@github.com:yourorg/server-[name].git
cd server-[name]

# 2. Configure
cp .env.example .env && $EDITOR .env
cp ansible/hosts.example ansible/hosts && $EDITOR ansible/hosts

# 3. Install Ansible dependencies (once per machine)
ansible-galaxy collection install -r scaffold/ansible/requirements.yml

# 4. Provision the server — run once as root on a fresh VPS
ansible-playbook -i ansible/hosts scaffold/ansible/bootstrap.yml

# 5. Harden and install Docker — idempotent, safe to re-run
ansible-playbook -i ansible/hosts scaffold/ansible/site.yml
```

## Deploying

```bash
ssh myserver
cd /opt/deploy
git clone --recurse-submodules git@github.com:yourorg/server-[name].git .
cp .env.example .env && $EDITOR .env
# create .env for each app too
docker compose up -d
```

## Adding an app

Create a folder in `apps/` with three files:

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

Then add one line to `docker-compose.yml`:
```yaml
include:
  - apps/myapp/docker-compose.yml
```

Caddy picks up `myapp.caddy` automatically — no changes to `Caddyfile` needed.

## Local development

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
docker compose up -d
docker compose exec caddy caddy trust   # once per machine — adds CA to keychain
```

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

## Security auditing

Run against a real provisioned VPS (not locally):

```bash
ansible-playbook -i ansible/hosts scaffold/ansible/audit-lynis.yml
ansible-playbook -i ansible/hosts scaffold/ansible/audit-openscap.yml
ansible-playbook -i ansible/hosts scaffold/ansible/audit-docker.yml
```

Reports saved to `reports/` (gitignored).

## Updating the scaffold

```bash
cd scaffold && git pull origin main && cd ..
git add scaffold
git commit -m "chore: update scaffold"
```

On server: `git pull --recurse-submodules && docker compose up -d`
