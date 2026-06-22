# apps/ntfy — self-hosted push notifications

Private [ntfy](https://ntfy.sh) server for security/integrity alerts (AIDE
changes, systemd unit failures, backup failures), so alert contents
(hostnames, paths, journal excerpts) never transit a third-party.

The host's `notify` role (scaffold) publishes here; your phone subscribes.

## Enable

1. `cp apps/ntfy/.env.example apps/ntfy/.env` and set `NTFY_ADMIN_PASSWORD`,
   `NTFY_BASE_URL`, `NTFY_ALERT_TOPIC`.
2. The root `docker-compose.yml` already includes `apps/ntfy/docker-compose.yml`
   (the container runs and publishes locally on `127.0.0.1:8080`).
3. `./deploy` — runs `apps/ntfy/deploy.sh` (fixes volume perms, creates the
   admin user, starts ntfy). Then create a token and wire `notify` (see the
   deploy output / scaffold notify role).
4. **Phone delivery (needs a domain):** point DNS `ntfy.<DOMAIN>` at this host,
   then `mv apps/ntfy/ntfy.caddy.disabled apps/ntfy/ntfy.caddy` and redeploy —
   Caddy serves `ntfy.<DOMAIN>` over HTTPS and you subscribe in the app with the
   token. The route ships disabled so Caddy doesn't request a cert for a domain
   that isn't pointed here yet.

## ⚠️ Single-box limitation (host-down)

ntfy runs **on the host it monitors**. If the host dies, is compromised, or is
network-partitioned, ntfy dies with it — so it cannot deliver a "host is down"
alert. This is inherent to self-hosting on one box.

**Mitigation — an external dead-man's-switch.** Run a cron on this host that
pings an *external* monitor on a schedule; if the pings stop, the external
service alerts you. Free options: [Healthchecks.io](https://healthchecks.io),
UptimeRobot. Example cron (every 10 min):

```cron
*/10 * * * * curl -fsS -m 10 https://hc-ping.com/<your-uuid> >/dev/null 2>&1
```

ntfy covers "something changed / a service failed" while the box is alive; the
dead-man's-switch covers "the box itself stopped." You want both.

## Security model

- `NTFY_AUTH_DEFAULT_ACCESS=deny-all` — topics are private; publish/subscribe
  require a token. Keep the topic name unguessable too.
- Hardened per CIS Docker §5 (non-root, cap_drop ALL, no-new-privileges,
  read-only rootfs, mem/pids limits, healthcheck).
- The publish port is bound to `127.0.0.1` only; remote access is HTTPS via Caddy.
