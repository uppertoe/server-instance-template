# Access review log — staging reference instance

Quarterly review of everything that can touch the box or its data (E8
restrict-admin revalidation at single-operator scale; VPDSS Std 4). The
maintenance-day issue prompts each entry; append newest first. Reviewing
takes ten minutes — the value is the dated trail.

Checklist per entry: `authorized_keys` on the host (deploy + admin) · auth
tier admin emails (when enabled) · S3 (backup, log-export), SMTP and ntfy
credentials still needed and least-privilege · GitHub collaborators, deploy
keys, branch-protection + code-owner enforcement intact · recovery bundle
current after any rotation.

---

## 2026-07-06 — recovery bundle created

- **Recovery bundle**: `recovery-bundle-rch-vps-20260706.tar.gz.enc` created
  (ansible/hosts + backup/config.env + backup/services/env-files.env),
  AES-256/PBKDF2, verified decryptable. Key stored separately (password
  manager); bundle to be stored offsite. Resolves the carried action item.
- **File hygiene**: `ansible/hosts` tightened 0644 → 0600.
- Still open: enable branch protection was completed via API this session;
  first live rebuild drill still pending.

Reviewed by: repo owner.

## 2026-07-05 — initial entry

- **SSH:** `deploy` and `admin` each hold the single operator ed25519 key;
  no other keys. Restricted mode on (`deploy` = wrapper-only sudo, no docker
  group).
- **Auth tier:** disabled; no admin emails configured.
- **Credentials:** backup S3 (write-scoped to `backups/` prefix), log-export
  S3 (write-only IAM), ntfy token — all single-purpose, in the gitignored
  inventory. No unused credentials identified.
- **GitHub:** single owner; no collaborators; CODEOWNERS present.
  *Branch protection + require-code-owner-review not yet enabled — carried
  as an action item.*
- **Recovery bundle:** to be generated on first real credential set (staging
  bundle pending) — carried as an action item.

Reviewed by: repo owner.
