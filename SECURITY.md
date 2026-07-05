# Security Policy

This is the server-instance template of the vps-scaffold platform. Hardening,
audit tooling and the security model live in the
[vps-base-template](https://github.com/uppertoe/vps-base-template) scaffold
(the `scaffold/` submodule); instance-side code here covers the compose stack,
deploy hooks and CI gates.

## Supported versions

The `main` branch only. Repos created from this template pick up fixes by
pulling template changes and bumping the `scaffold` submodule (Renovate
automates the submodule bumps).

## Reporting a vulnerability

Use **GitHub private vulnerability reporting** (Security tab → "Report a
vulnerability") on this repository — or on vps-base-template if the issue is
in a hardening role, audit playbook, or the Caddy base. If unsure, report
here; it will be routed.

Please include the affected file, an impact sketch, and reproduction steps if
available. Expect acknowledgement within a few days; fixes land as ordinary
PRs proven by this repo's CI.

## Scope notes

- The trust model for the auth gateway's `Remote-*` headers, the per-app
  network isolation, and the repo-to-root deploy boundary are documented in
  `scaffold/docs/07-auth.md`, `04-server-repo.md` and `05-access-model.md` —
  reports demonstrating a bypass of any of them are especially valuable.
- Deliberate exceptions (published reverse-proxy ports etc.) are in the
  scaffold's docs/08 exceptions register.
