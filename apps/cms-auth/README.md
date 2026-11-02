# apps/cms-auth — gateway-gated commit broker for Decap CMS

Backs the in-browser [Decap CMS](https://decapcms.org/) on the estate's Hugo
sites **without giving editors GitHub accounts**. Editors sign in through the
estate gateway (`apps/auth`); the broker commits through ONE shared **GitHub
App**, stamping each commit's author with the signed-in editor. The App private
key is turned into short-lived installation tokens **server-side** and never
reaches the browser.

Two jobs, both on the `cms-auth.<DOMAIN>` host:

- **`/auth`** — the CMS opens it in a popup. It sits behind the gateway
  (members of `cms-editors` only); the broker reads the editor from the
  gateway's `Remote-Email` / `Remote-Groups`, trusted only alongside the
  `X-Gateway-Secret` that Caddy injects, and hands the CMS a signed,
  short-lived **session token** (not a GitHub credential) via `postMessage`.
- **`/api/*`** — the commit proxy the CMS points `api_root` at. It is public,
  because the CMS calls it cross-origin without the gateway cookie, and it is
  authenticated by the session token. It injects the shared App installation
  token, rewrites each commit's **author** to the editor (committer = the bot),
  and forwards to GitHub.

**One broker serves every site** — each Hugo site points its Decap config here
and is added to `ALLOWED_ORIGINS` / `ALLOWED_REPOS`. Source/image:
`ghcr.io/uppertoe/cms-auth` (run here with `AUTH_MODE=gateway`).

The commit author's name is built from the editor's email address
("jane.citizen@…" becomes "Jane Citizen"), because the gateway knows
addresses, not display names.

## Enable (automated)

```bash
bash apps/cms-auth/setup.sh
```

`setup.sh` does everything machine-doable and prompts only for what a human must
provide: it prints a **pre-filled GitHub App creation URL** (Contents:write, no
webhook), writes `CMS_AUTH_GATEWAY_SECRET` to the root `.env`, generates
`SESSION_SECRET`, base64-encodes the App private key into the app `.env` (mode
600), and re-renders the Caddy bundle. You still (a) click *Create* + *Install*
on the App and paste back three values, and (b) put your editors in the
`cms-editors` group on the gateway's admin Groups page.

### What it automates vs. what stays manual

| Step | Automated by `setup.sh` | Manual |
| --- | --- | --- |
| GitHub App create/install | pre-filled URL, key→base64, `.env` write | click Create + Install; paste App ID / Installation ID |
| Gateway secret (root `.env`) | ✅ | — |
| `SESSION_SECRET`, `.env` assembly, Caddy render | ✅ | — |
| Editors → `cms-editors` group | — | add each editor on the gateway |

### Manual equivalent

If you'd rather do it by hand, the steps `setup.sh` performs are: create the
GitHub App (Contents R/W, install on the CMS repo → App ID + Installation ID +
private key); set `CMS_AUTH_GATEWAY_SECRET` (`openssl rand -hex 32`) in the root
`.env`; fill `apps/cms-auth/.env` (`ALLOWED_ORIGINS`, `ALLOWED_REPOS`,
`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_B64` =
`base64 -w0` of the PEM, `COMMITTER_EMAIL`, `SESSION_SECRET` =
`openssl rand -hex 32`); then `bash scaffold/docker/render-caddy-routes.sh`.

## Point a Hugo site at it

In each site's `static/admin/config.yml` (served at `<site>/admin/`):

```yaml
backend:
  name: github
  repo: anaes-data-lab/<hugo-site-repo>
  branch: main
  base_url: https://cms-auth.<DOMAIN>       # sign-in popup (/auth, gateway-gated)
  api_root: https://cms-auth.<DOMAIN>/api    # commit proxy (author-stamped, bot-committed)
```

Then add that site's `admin/` origin to `ALLOWED_ORIGINS` and its repo to
`ALLOWED_REPOS`, and install the GitHub App on that repo. The `/admin/` page can
sit behind the site's normal reading gate — editing authority is enforced at the
broker (`cms-editors`), not at the page.
