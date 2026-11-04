# Secrets

Every secret this server needs is kept here, encrypted with
[SOPS](https://github.com/getsops/sops) and [age](https://age-encryption.org),
and committed. At each deploy the root-run wrapper decrypts the files with the
server's key and writes the plaintext files Compose already reads:

| Encrypted file | Rendered on the server as |
|---|---|
| `secrets/.env.sops` | `.env` (the root file: `DOMAIN` and the gateway secrets) |
| `secrets/apps/<app>/.env.sops` | `apps/<app>/.env` |
| `secrets/backup/config.env.sops` | `/etc/restic/config.env` |
| `secrets/backup/services/<name>.env.sops` | `/etc/restic/services/<name>.env` |
| `secrets/recovery.sops` | never rendered; holds the inventory for a rebuild |

The design, the deploy flow and the rebuild drill are in
`scaffold/docs/13-secrets.md`. CI fails if a file under this directory is not
fully encrypted or if a plaintext env file is ever tracked.

## Putting the keys in

Three public keys go into `.sops.yaml` at the repo root. Only the public halves
are recorded there. No private key is committed, placed in CI or copied to a
Renovate runner.

1. The server key is created by the first site play, which prints its public
   half. The same value is kept in `/etc/vps-scaffold/age/key.pub` on the
   server, readable with `ssh <host> cat /etc/vps-scaffold/age/key.pub`.
2. The owner key is created on the laptop with
   `age-keygen -o ~/.config/sops/age/keys.txt`. Put
   `export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt` in the shell profile
   and copy the public key the command prints.
3. The recovery key is created with `age-keygen -o recovery-key.txt`. Store the
   whole file in the password manager, note its public key, then delete the
   file. The owner and recovery keys are the same for every server you run.

Replace the three placeholders in `.sops.yaml` with those public keys and
commit. The recovery file is encrypted to the owner and recovery keys only,
because the server never needs to read it.

## Writing a secret

Work on the laptop, in the server repo, with the app's `.env.example` beside
you. SOPS opens your editor on the decrypted text and re-encrypts it on save:

```bash
sops --input-type dotenv --output-type dotenv secrets/apps/<app>/.env.sops
```

Commit the file signed and push. The next deploy renders it, and a file that
fails to decrypt stops the deploy before any container is touched. Never edit
a `.env` file on the server, because the next deploy overwrites it.

The inventory goes into `secrets/recovery.sops` as one base64 value,
`ANSIBLE_HOSTS_B64=$(base64 < ansible/hosts | tr -d '\n')`, so a rebuild
needs only this repository and the recovery key.

## Retiring a key

Retiring a key, or suspecting one has been exposed, means rotating every
secret it could decrypt, not only re-encrypting the files. Git history keeps
the old ciphertext, and the old key still opens it.
