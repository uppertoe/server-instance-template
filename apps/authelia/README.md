# Authelia -- OIDC provider (SSO)

A self-hosted [Authelia](https://www.authelia.com/) instance acting as an
**OpenID Connect provider** on `sso.<DOMAIN>`, for apps that speak OIDC (e.g. the
[cms-auth](../cms-auth) CMS commit broker).

This is **separate** from the forward-auth gateway in [`apps/auth`](../auth):

| | `apps/auth` (vps-scaffold-auth) | `apps/authelia` (this) |
|---|---|---|
| Role | `forward_auth` gateway (`import protected`) | OIDC provider (apps redirect here) |
| Login | passwordless email one-time code | username + password |
| Users | allowed email domains / admin list | hand-maintained `users_database.yml` |
| Use it for | apps with no auth of their own | apps that support OIDC SSO |

They share no users. Pick the gateway for header-based protection of arbitrary
apps; pick Authelia when an app has native OIDC and you want it to own login.

## What you maintain

- **`users/users_database.yml`** -- the user list (gitignored; lives on the
  server at mode 600 inside the `users/` directory, seeded from
  `users_database.yml.example` by `deploy.sh`). Each user has a display name, an
  argon2id password hash, an email, and **groups**. It sits in its own directory
  (rather than a bare file) so Authelia `watch: true` hot-reloads edits and the
  invite portal (apps/users) can write it via atomic rename -- see the mount
  note in `docker-compose.yml`.
- **`configuration.yml`** -- non-secret, committed. Holds the OIDC client
  registrations and per-client authorization policies.
- **`.env`** -- the four `AUTHELIA_*` secrets plus the SES SMTP settings
  (`AUTHELIA_NOTIFIER_SMTP_*`) (gitignored; see `.env.example`).
- **`secrets/*.hash`** -- per-client OIDC secret **hashes**, one file each
  (gitignored; seeded from `secrets/*.hash.example` by `deploy.sh`). These are
  files rather than env vars because a pbkdf2 hash contains `$`, which Docker
  Compose interpolates away in env values -- a silent footgun.

## Enabling it

1. `cp apps/authelia/.env.example apps/authelia/.env` and fill the four
   `openssl rand -hex 64` secrets **and** the SES SMTP settings
   (`AUTHELIA_NOTIFIER_SMTP_*` -- see [Email](#email-aws-ses) below).
2. Uncomment the `apps/authelia` include in the root `docker-compose.yml`.
3. Point DNS for `sso.<DOMAIN>` at the host, then deploy (`~/deploy`, which runs
   `deploy.sh`: seeds the user file, generates the OIDC issuer key, fixes perms).

## Provisioning a user

Add the user; **they set their own password** via self-service reset — which works
behind RCH's Defender Safe Links thanks to the
[interstitial](#self-service-reset--the-safe-links-interstitial). You never set or
hand out a password.

> Once the invite portal (apps/users) is deployed, prefer it over hand-editing
> for non-technical admins — it does all of the below (plus group assignment)
> from a web form. The manual flow stays valid as a break-glass path.

1. Add the user to `apps/authelia/users/users_database.yml` on the server with
   their `displayname`, `email`, the `groups` that grant access (see the role
   mapping below), and a **throwaway** `password` hash (the file backend needs
   *some* hash; the user replaces it):
   ```bash
   docker run --rm ghcr.io/authelia/authelia \
     authelia crypto hash generate argon2 --random
   ```
2. With `watch: true` (now the default here) Authelia hot-reloads the edit
   within ~1s; no restart needed. (A restart still works if you prefer.)
3. Tell the user: go to `https://sso.<DOMAIN>`, click **Reset password?**, enter
   their **username**, and follow the email to set their own password.

To set a password yourself instead (e.g. break-glass), use
`authelia crypto hash generate argon2 --password '…'` for step 1 and skip step 3 —
the users file is mounted read-write, so both admin-set and self-service work.

## Email (AWS SES)

Self-service password-reset emails are sent over SMTP via AWS SES (the same domain
identity as [`apps/auth`](../auth)). Mint SMTP creds with
[`scripts/aws-ses-setup.py`](../../scripts/aws-ses-setup.py) (the SMTP user is
scoped to send as `*@<domain>`, so the auth service's creds can be reused) and set
in `apps/authelia/.env`:

- `AUTHELIA_NOTIFIER_SMTP_ADDRESS` -- e.g.
  `submission://email-smtp.ap-southeast-2.amazonaws.com:587`
- `AUTHELIA_NOTIFIER_SMTP_USERNAME` / `AUTHELIA_NOTIFIER_SMTP_PASSWORD`
- `AUTHELIA_NOTIFIER_SMTP_SENDER` -- a From address at the SES-verified domain

The SMTP startup probe is disabled (so an unconfigured SES doesn't block startup).
Production SES access is needed to email arbitrary `@rch.org.au` recipients.

## Self-service reset & the Safe Links interstitial

Authelia's password reset is a one-time email **link**, and RCH's Microsoft Defender
Safe Links **detonates** that link on delivery — it renders the page, runs its JS,
and fires the `identity/finish` / revoke XHRs, consuming the one-time token before the
user can click (verified live: a Microsoft IP, rotating its User-Agent, hit the
endpoints ~25s after the request, before the email even arrived). The bare link is
therefore dead for every `@rch.org.au` mailbox, and there is no Authelia setting or
mail-filter exemption available to us that fixes it.

The defence lives in [`authelia.caddy`](authelia.caddy): Caddy intercepts the reset
and revoke links and serves **static gate pages** ([`reset-gate.html`](reset-gate.html),
[`revoke-info.html`](revoke-info.html)) instead of Authelia's SPA — so Authelia's
auto-consuming JS never loads for whoever opens the bare link. The reset gate asks the
user to type their email and click Continue, which redirects to
`…/reset-password/step2?token=…&go=1`; **only requests carrying `go=1` are proxied
through to the real Authelia reset**. A scanner renders the gate and runs its JS but
won't fill the field, so it never produces `go=1` and never reaches a consuming
endpoint — it dead-ends on a static page. A human types their email and proceeds
normally. Verified end-to-end against the live scanner: it hit both gate pages and
reached **no** consuming endpoint; the token survived.

Limits worth knowing:
- The gate only checks the field is non-empty and email-shaped — it's a "make a human
  act" gate, not validation of the address (identity is the token).
- Self-service **revoke** ("this wasn't me") is dropped; the token just expires.
- It depends on Authelia's `/reset-password/step2` path, which could shift on a major
  Authelia upgrade — re-test after upgrades.

## Adding an OIDC client

Each client is one entry under `identity_providers.oidc.clients` in
`configuration.yml`, plus an authorization policy that lists the groups allowed
to use it. To register a new app:

1. Mint a client secret + its hash:
   ```bash
   docker compose run --rm authelia \
     authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72
   ```
   The **Random Password** is the plaintext (goes in the app's config); the
   **Digest** (`$pbkdf2-sha512$...`) is what Authelia stores.
2. Put the **Digest** in `secrets/<client>.hash` (a single line, raw `$` -- no
   escaping; it's a file, not an env value) and reference it from the client's
   `client_secret` with `'{{ secret "/config/secrets/<client>.hash" }}'` (as the
   pre-registered cms-auth client does). Put the **Random Password** in the app's
   own config. Add the rest of the `clients:` entry: `client_id`, `redirect_uris`
   (**exact match**, no wildcards), `scopes`, and an `authorization_policy`.
3. Add an `authorization_policies` entry gating the client to the right groups.

The discovery URL for clients is
`https://sso.<DOMAIN>/.well-known/openid-configuration`.

## Groups -> app access

Each OIDC client's `authorization_policy` (in `configuration.yml`) lists the
groups whose members may obtain a token for it. The bundled example:

| Group in `users_database.yml` | Grants |
|---|---|
| `cms-editors` | sign in to the CMS commit broker ([`apps/cms-auth`](../cms-auth)) and commit as themselves |

A user in none of a client's groups is denied a token for it at the provider.

Separately, the `cms-editors` group gates the Decap CMS commit broker: only its
members obtain a token for the `cms-auth` client (the `cms_auth` authorization
policy), and the broker re-checks the group. See [`apps/cms-auth`](../cms-auth).

## Notes

- **Sessions are persisted in Redis** (`authelia-redis`, `session.redis` in
  `configuration.yml`), with an append-only file on the `authelia_redis_data`
  volume — so they survive an Authelia recreate/redeploy and a host reboot
  (deploys force-recreate Authelia, which would otherwise drop every in-memory
  session). Redis is on the `internal: true` `authelia_internal` network only
  (no ports, no other tenant), so no Redis password is used; `deploy.sh` chowns
  its volume to 999:999.
- **Self-service password reset is ENABLED** and works behind Defender Safe Links
  via a Caddy interstitial (see
  [Self-service reset](#self-service-reset--the-safe-links-interstitial)); the users
  file is mounted **read-write** so resets persist. The user list is a
  **directory** mount with `watch: true`, so both resets and host-side
  hand-edits hot-reload within ~1s — no restart needed (a single-file mount
  used to pin the inode and defeat the watcher; see `docker-compose.yml`).
- The OIDC **issuer signing key** is generated on the server (`/data/oidc.key.pem`
  on the `authelia_data` volume) and never enters git. Back up that volume if you
  don't want clients to need re-consent after a rebuild.
- Pin the image to a digest in production (Renovate does this) rather than
  `:latest`.
