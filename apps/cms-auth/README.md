# apps/cms-auth — OIDC-gated commit broker for Decap CMS

Backs the in-browser [Decap CMS](https://decapcms.org/) on the estate's Hugo
sites **without giving editors GitHub accounts**. Editors sign in with Authelia
(OIDC); the broker commits through ONE shared **GitHub App**, stamping each
commit's author with the signed-in editor. The App private key is turned into
short-lived installation tokens **server-side** and never reaches the browser.

Two jobs, both on the public `cms-auth.<DOMAIN>` host:

- **`/auth` + `/callback`** — run the OIDC login popup against Authelia, read the
  editor's identity from `userinfo`, and hand the CMS a signed, short-lived
  **session token** (not a GitHub credential) via `postMessage`.
- **`/api/*`** — the commit proxy the CMS points `api_root` at. Validates the
  session token, injects the shared App installation token, rewrites each
  commit's **author** to the editor (committer = the bot), and forwards to
  GitHub.

**One broker serves every site** — each Hugo site points its Decap config here
and is added to `ALLOWED_ORIGINS` / `ALLOWED_REPOS`. Source/image:
`ghcr.io/uppertoe/cms-auth`.

It is **public** by design (Authelia redirects the browser to `/callback`, and
the CMS calls `/api` cross-origin), so it is **not** behind the login wall.
Protection = the OIDC login + the `cms-editors` group policy at Authelia + the
signed session token the proxy validates.

## Enable (automated)

```bash
bash apps/cms-auth/setup.sh
```

`setup.sh` does everything machine-doable and prompts only for what a human must
provide: it prints a **pre-filled GitHub App creation URL** (Contents:write, no
webhook), mints the **Authelia OIDC client secret** and writes both the hash
(`apps/authelia/secrets/cms-auth.hash`) and the plaintext (`OIDC_CLIENT_SECRET`),
generates `SESSION_SECRET`, base64-encodes the App private key into the `.env`
(mode 600), and re-renders the Caddy bundle. You still (a) click *Create* +
*Install* on the App and paste back three values, and (b) put your editors in the
`cms-editors` group. Then re-pin the image digest (below) and deploy.

### What it automates vs. what stays manual

| Step | Automated by `setup.sh` | Manual |
| --- | --- | --- |
| GitHub App create/install | pre-filled URL, key→base64, `.env` write | click Create + Install; paste App ID / Installation ID |
| Authelia client secret | mint + hash + `.env` | — |
| `SESSION_SECRET`, `.env` assembly, Caddy render | ✅ | — |
| Editors → `cms-editors` group | — | add each editor |
| Image digest pin | pinned; Renovate-maintained | — |

The Authelia `cms-auth` client + `cms_auth` policy already ship in
`apps/authelia/configuration.yml`. To turn the app on: rename
`apps/cms-auth/cms-auth.caddy.disabled` → `cms-auth.caddy` and uncomment the
`apps/cms-auth/docker-compose.yml` include in the root `docker-compose.yml`
(**Authelia must be enabled too** — see [`apps/authelia`](../authelia)).

### Manual equivalent

If you'd rather do it by hand, the steps `setup.sh` performs are: create the
GitHub App (Contents R/W, install on the CMS repo → App ID + Installation ID +
private key); mint the Authelia secret (`apps/authelia/README.md` "Adding an OIDC
client"); fill `apps/cms-auth/.env` (`ALLOWED_ORIGINS`, `ALLOWED_REPOS`,
`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_B64` =
`base64 -w0` of the PEM, `COMMITTER_EMAIL`, `OIDC_CLIENT_SECRET`, `SESSION_SECRET`
= `openssl rand -hex 32`); then `bash scaffold/docker/render-caddy-routes.sh`.

## Point a Hugo site at it

In each site's `static/admin/config.yml` (served at `<site>/admin/`):

```yaml
backend:
  name: github
  repo: anaes-data-lab/<hugo-site-repo>
  branch: main
  base_url: https://cms-auth.<DOMAIN>       # OIDC login popup (/auth, /callback)
  api_root: https://cms-auth.<DOMAIN>/api    # commit proxy (author-stamped, bot-committed)
```

Then add that site's `admin/` origin to `ALLOWED_ORIGINS` and its repo to
`ALLOWED_REPOS`, and install the GitHub App on that repo. The `/admin/` page can
sit behind the site's normal reading gate — editing authority is enforced at the
broker (OIDC + `cms-editors`), not at the page.
