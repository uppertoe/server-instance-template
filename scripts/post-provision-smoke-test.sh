#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/post-provision-smoke-test.sh [HOST_ALIAS] [OPTIONS]

Checks a real provisioned VPS over SSH.

Arguments:
  HOST_ALIAS         SSH host alias from ~/.ssh/config (default: myserver)

Options:
  --require-backup   Fail if the backup system is not deployed/configured
  --skip-backup      Skip backup-related checks entirely
  -h, --help         Show this help
EOF
}

HOST_ALIAS="myserver"
REQUIRE_BACKUP=false
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --require-backup)
      REQUIRE_BACKUP=true
      shift
      ;;
    --skip-backup)
      SKIP_BACKUP=true
      shift
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      HOST_ALIAS="$1"
      shift
      ;;
  esac
done

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

header() {
  echo
  echo "== $* =="
}

pass() {
  echo "[PASS] $*"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "[FAIL] $*" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
  echo "[WARN] $*"
  WARN_COUNT=$((WARN_COUNT + 1))
}

remote() {
  local cmd="$1"
  ssh "$HOST_ALIAS" "bash -lc $(printf '%q' "$cmd")"
}

check_remote() {
  local label="$1"
  local cmd="$2"
  if remote "$cmd" >/tmp/post-provision-smoke.out 2>/tmp/post-provision-smoke.err; then
    pass "$label"
  else
    fail "$label"
    if [[ -s /tmp/post-provision-smoke.err ]]; then
      sed 's/^/  /' /tmp/post-provision-smoke.err >&2
    elif [[ -s /tmp/post-provision-smoke.out ]]; then
      sed 's/^/  /' /tmp/post-provision-smoke.out >&2
    fi
  fi
}

cleanup() {
  rm -f /tmp/post-provision-smoke.out /tmp/post-provision-smoke.err
}

trap cleanup EXIT

header "Connection"

if ssh -G "$HOST_ALIAS" >/tmp/post-provision-smoke.out 2>/tmp/post-provision-smoke.err; then
  pass "SSH config resolves for $HOST_ALIAS"
else
  fail "SSH config resolves for $HOST_ALIAS"
  sed 's/^/  /' /tmp/post-provision-smoke.err >&2
  exit 1
fi

check_remote "SSH login works" "true"
check_remote "Connected user is deploy" "[[ \$(whoami) == 'deploy' ]]"
check_remote "Passwordless sudo works" "sudo -n true"

header "Server"
check_remote "/opt/deploy exists and is owned by deploy" "[[ -d /opt/deploy ]] && [[ \$(stat -c '%U:%G' /opt/deploy) == 'deploy:deploy' ]]"
check_remote "~/deploy helper exists and is executable" "[[ -x /home/deploy/deploy ]]"
check_remote "Docker CLI is installed" "docker --version >/dev/null"
check_remote "Docker Compose plugin is installed" "docker compose version >/dev/null"
check_remote "Docker service is active" "sudo systemctl is-active --quiet docker"
check_remote "Docker service is enabled" "sudo systemctl is-enabled --quiet docker"
check_remote "docker-prune timer is active" "sudo systemctl is-active --quiet docker-prune.timer"
check_remote "docker-prune timer is enabled" "sudo systemctl is-enabled --quiet docker-prune.timer"

header "SSH Hardening"
check_remote "sshd disables password auth" "sudo sshd -T | grep -Fx 'passwordauthentication no' >/dev/null"
check_remote "sshd disables root login" "sudo sshd -T | grep -Fx 'permitrootlogin no' >/dev/null"
check_remote "sshd restricts login to deploy" "sudo sshd -T | grep -Fx 'allowusers deploy' >/dev/null"
check_remote "sshd sets ClientAliveCountMax to 2" "sudo sshd -T | grep -Fx 'clientalivecountmax 2' >/dev/null"
check_remote "sshd sets ClientAliveInterval to 300" "sudo sshd -T | grep -Fx 'clientaliveinterval 300' >/dev/null"
check_remote "sshd sets MaxSessions to 2" "sudo sshd -T | grep -Fx 'maxsessions 2' >/dev/null"
check_remote "sshd sets MaxAuthTries to 3" "sudo sshd -T | grep -Fx 'maxauthtries 3' >/dev/null"
check_remote "sshd sets LoginGraceTime to 30s" "sudo sshd -T | grep -Fx 'logingracetime 30' >/dev/null"
check_remote "sshd sets LogLevel to INFO" "sudo sshd -T | grep -Fx 'loglevel INFO' >/dev/null"
check_remote "SSH banner points at /etc/issue.net" "sudo sshd -T | grep -Fx 'banner /etc/issue.net' >/dev/null"
check_remote "SSH banner file is present" "[[ -f /etc/issue.net ]]"
check_remote "Root password is locked" "sudo passwd -S root | awk '{print \$2}' | grep -qx 'L'"
check_remote "fail2ban is active" "sudo systemctl is-active --quiet fail2ban"
check_remote "fail2ban is enabled" "sudo systemctl is-enabled --quiet fail2ban"
check_remote "auditd is absent" "! dpkg -s auditd >/dev/null 2>&1"

header "Firewall"
check_remote "UFW is active" "sudo ufw status | grep -F 'Status: active' >/dev/null"
check_remote "UFW allows SSH/HTTP/HTTPS" "status=\$(sudo ufw status); [[ \$status == *'22/tcp'* && \$status == *'80/tcp'* && \$status == *'443/tcp'* && \$status == *'443/udp'* ]]"

header "Baseline Hardening"
check_remote "pwquality is installed" "dpkg -s libpam-pwquality >/dev/null 2>&1"
check_remote "apparmor-utils is installed" "dpkg -s apparmor-utils >/dev/null 2>&1"
check_remote "PAM faillock profile is present" "[[ -f /usr/share/pam-configs/vps-faillock ]]"
check_remote "TMOUT and umask are configured" "grep -F 'export TMOUT=900' /etc/profile.d/99-vps-scaffold-session.sh >/dev/null && grep -F 'umask 027' /etc/profile.d/99-vps-scaffold-session.sh >/dev/null"
check_remote "/etc/profile includes TMOUT and umask" "grep -F 'export TMOUT=900' /etc/profile >/dev/null && grep -F 'umask 027' /etc/profile >/dev/null"
check_remote "/etc/bash.bashrc includes umask" "grep -F 'umask 027' /etc/bash.bashrc >/dev/null"
check_remote "Inactive password lock default is configured" "grep -Fx 'INACTIVE=30' /etc/default/useradd >/dev/null"
check_remote "cron.allow exists" "[[ -f /etc/cron.allow ]]"
check_remote "at.allow exists" "[[ -f /etc/at.allow ]]"
check_remote "sudo logging is configured" "sudo grep -F 'Defaults logfile=\"/var/log/sudo.log\"' /etc/sudoers.d/01-vps-scaffold-logging >/dev/null && sudo grep -F 'Defaults use_pty' /etc/sudoers.d/01-vps-scaffold-logging >/dev/null && sudo grep -F 'Defaults timestamp_timeout=0' /etc/sudoers.d/01-vps-scaffold-logging >/dev/null"
check_remote "timesyncd config is present" "[[ -f /etc/systemd/timesyncd.conf.d/99-vps-scaffold.conf ]]"
check_remote "timesyncd config includes expected NTP servers" "grep -F 'NTP=time.cloudflare.com time.google.com' /etc/systemd/timesyncd.conf.d/99-vps-scaffold.conf >/dev/null && grep -F 'FallbackNTP=0.pool.ntp.org 1.pool.ntp.org' /etc/systemd/timesyncd.conf.d/99-vps-scaffold.conf >/dev/null"

if ! "$SKIP_BACKUP"; then
  header "Backups"

  if remote "[[ -f /opt/backup/backup.sh || -f /etc/systemd/system/backup.service || -d /etc/restic ]]" >/dev/null 2>/dev/null; then
    pass "Backup system is deployed"
    check_remote "backup.sh is installed" "[[ -x /opt/backup/backup.sh ]]"
    check_remote "restore.sh is installed" "[[ -x /opt/backup/restore.sh ]]"
    check_remote "restic is installed" "restic version >/dev/null"
    check_remote "/etc/restic/config.env is present and locked down" "[[ -f /etc/restic/config.env ]] && [[ \$(sudo stat -c '%U:%G:%a' /etc/restic/config.env) == 'root:root:600' ]]"
    check_remote "backup.timer is active" "sudo systemctl is-active --quiet backup.timer"
    check_remote "backup.timer is enabled" "sudo systemctl is-enabled --quiet backup.timer"
    check_remote "backup-verify.timer is active" "sudo systemctl is-active --quiet backup-verify.timer"
    check_remote "backup-verify.timer is enabled" "sudo systemctl is-enabled --quiet backup-verify.timer"

    service_count="$(remote "find /etc/restic/services -maxdepth 1 -type f -name '*.env' | wc -l | tr -d ' '" 2>/dev/null || echo 0)"
    if [[ "$service_count" =~ ^[0-9]+$ ]] && (( service_count > 0 )); then
      pass "Backup service configs exist ($service_count)"
      check_remote "backup.sh dry-run succeeds" "sudo /opt/backup/backup.sh --dry-run >/dev/null"
    else
      if "$REQUIRE_BACKUP"; then
        fail "Backup service configs exist"
      else
        warn "Backup is deployed but no /etc/restic/services/*.env files exist yet; skipped backup.sh dry-run"
      fi
    fi
  else
    if "$REQUIRE_BACKUP"; then
      fail "Backup system is deployed"
    else
      warn "Backup system not deployed yet; rerun with --require-backup after ansible/backup.yml"
    fi
  fi
fi

header "Summary"
echo "Pass: $PASS_COUNT"
echo "Warn: $WARN_COUNT"
echo "Fail: $FAIL_COUNT"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
