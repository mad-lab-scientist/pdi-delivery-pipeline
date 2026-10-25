#!/usr/bin/env bash
# =============================================================================
# server-baseline.sh: secure baseline for a new Linux server, one script for Debian/Ubuntu,
# RHEL/Rocky/AlmaLinux and SUSE/openSUSE.
#
#   sudo ./server-baseline.sh                       interactive: prompts for anything not given
#   sudo ./server-baseline.sh --hostname web01 --timezone America/Chicago \
#        --ntp "0.pool.ntp.org,1.pool.ntp.org" --admin-user opsadmin \
#        --admin-key "ssh-ed25519 AAAA... ops@laptop" --mgmt-cidr 10.20.3.0/25 --yes
#   sudo ./server-baseline.sh --dry-run             show every change without making it
#
# What it does (idempotent; existing files are backed up as *.bak.<timestamp>):
#   hostname and timezone, chrony NTP, an admin user with sudo and an SSH key, SSH hardening
#   (validated with sshd -t before reload), host firewall allowing SSH only from the management
#   network (ufw or firewalld), automatic security updates (unattended-upgrades, dnf-automatic, or a
#   zypper patch timer), kernel network hardening (sysctl) and auditd.
# Password authentication is disabled only when an SSH key was installed, so the script cannot
# lock you out; the firewall step refuses a management CIDR that excludes your current session.
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

HOSTNAME_NEW="" TIMEZONE="" NTP_SERVERS="" ADMIN_USER="" ADMIN_KEY="" MGMT_CIDR="" SSH_PORT=22
DO_FIREWALL=1 DO_UPDATES=1 AUTO_REBOOT=""
usage() { sed -n '3,22p' "$0"; }
while [[ $# -gt 0 ]]; do
  case $1 in
    --hostname) HOSTNAME_NEW=$2; shift 2 ;;
    --timezone) TIMEZONE=$2; shift 2 ;;
    --ntp) NTP_SERVERS=${2//,/ }; shift 2 ;;
    --admin-user) ADMIN_USER=$2; shift 2 ;;
    --admin-key) ADMIN_KEY=$2; shift 2 ;;
    --mgmt-cidr) MGMT_CIDR=$2; shift 2 ;;
    --ssh-port) SSH_PORT=$2; shift 2 ;;
    --no-firewall) DO_FIREWALL=0; shift ;;
    --no-auto-updates) DO_UPDATES=0; shift ;;
    --auto-reboot) AUTO_REBOOT=$2; shift 2 ;;   # HH:MM for unattended reboots after updates (Debian family)
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[[ $DRY_RUN == 1 ]] || require_root
detect_os
info "detected ${OS_NAME} (family ${OS_FAMILY}, package manager ${PKG})"
[[ $OS_FAMILY =~ ^(debian|rhel|suse)$ ]] || die "server-baseline supports Debian, RHEL and SUSE families"

is_timezone() { [[ -f "/usr/share/zoneinfo/$1" ]]; }
is_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] && [[ $1 != root ]]; }
is_server_list() { local s; for s in $1; do is_ipv4 "$s" || is_fqdn "$s" || return 1; done; }

client_ip=${SSH_CONNECTION:-}; client_ip=${client_ip%% *}
default_cidr=$([[ -n "${SSH_CONNECTION:-}" ]] && echo "${client_ip}/32" || echo "")
current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##' || echo UTC)

ask HOSTNAME_NEW "Hostname" "$(uname -n | cut -d. -f1)" is_hostname
ask TIMEZONE "Timezone (e.g. America/Chicago)" "${current_tz:-UTC}" is_timezone
ask NTP_SERVERS "NTP servers (space separated)" "0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org" is_server_list
ask ADMIN_USER "Admin username" "opsadmin" is_user
if [[ -z "$ADMIN_KEY" && $ASSUME_YES == 0 && -t 0 ]]; then
  read -r -p "Admin SSH public key (paste; blank to skip): " ADMIN_KEY
fi
if [[ -n "$ADMIN_KEY" ]]; then
  if command -v ssh-keygen >/dev/null; then
    ssh-keygen -lf - <<< "$ADMIN_KEY" >/dev/null 2>&1 || die "the admin key is not a valid OpenSSH public key"
  elif [[ ! $ADMIN_KEY =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com)\ [A-Za-z0-9+/=]+ ]]; then
    die "the admin key does not look like an OpenSSH public key"
  fi
fi
is_port "$SSH_PORT" || die "invalid SSH port: $SSH_PORT"
if [[ $DO_FIREWALL == 1 ]]; then
  ask MGMT_CIDR "Management network allowed to SSH (CIDR)" "${default_cidr:-0.0.0.0/0}" is_cidr
fi

# ---------------------------------------------------------------- packages
step "Packages"
case $OS_FAMILY in
  debian) run apt-get update -q
          pkgs=(chrony openssh-server auditd sudo curl ca-certificates)
          [[ $DO_FIREWALL == 1 ]] && pkgs+=(ufw)
          [[ $DO_UPDATES == 1 ]] && pkgs+=(unattended-upgrades) ;;
  rhel)   pkgs=(chrony openssh-server audit sudo curl ca-certificates policycoreutils-python-utils)
          [[ $DO_FIREWALL == 1 ]] && pkgs+=(firewalld)
          [[ $DO_UPDATES == 1 ]] && pkgs+=(dnf-automatic) ;;
  suse)   run zypper --non-interactive --quiet refresh
          pkgs=(chrony openssh-server audit sudo curl ca-certificates)
          [[ $DO_FIREWALL == 1 ]] && pkgs+=(firewalld) ;;
esac
pkg_install "${pkgs[@]}"

# ---------------------------------------------------------------- hostname and time
step "Hostname ${HOSTNAME_NEW}, timezone ${TIMEZONE}"
if has_systemd; then
  run hostnamectl set-hostname "$HOSTNAME_NEW"
  run timedatectl set-timezone "$TIMEZONE"
else
  printf '%s\n' "$HOSTNAME_NEW" | write_file /etc/hostname
  run ln -sfn "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
fi
if ! grep -qE "^[0-9.]+[[:space:]].*\b${HOSTNAME_NEW}\b" /etc/hosts 2>/dev/null; then
  { grep -v -E '^127\.0\.1\.1[[:space:]]' /etc/hosts; printf '127.0.1.1\t%s\n' "$HOSTNAME_NEW"; } | write_file /etc/hosts
fi

step "NTP (chrony): ${NTP_SERVERS}"
chrony_conf=$([[ $OS_FAMILY == debian ]] && echo /etc/chrony/chrony.conf || echo /etc/chrony.conf)
chrony_service=$([[ $OS_FAMILY == debian ]] && echo chrony || echo chronyd)
if [[ -f $chrony_conf || $DRY_RUN == 1 ]]; then
  {
    # Keep the distribution's settings, replace its time sources with ours.
    sed -e '/^# BEGIN server-baseline/,/^# END server-baseline/d' -e 's/^\(pool\|server\) /#&/' "$chrony_conf" 2>/dev/null || true
    echo "# BEGIN server-baseline"
    for s in $NTP_SERVERS; do echo "server $s iburst"; done
    echo "# END server-baseline"
  } | write_file "$chrony_conf"
fi
if has_systemd; then run systemctl enable --now "$chrony_service"; fi

# ---------------------------------------------------------------- admin user
step "Admin user ${ADMIN_USER}"
if id "$ADMIN_USER" >/dev/null 2>&1; then
  ok "user ${ADMIN_USER} exists"
else
  run useradd --create-home --shell /bin/bash --comment "Administrator" "$ADMIN_USER"
fi
printf '%s ALL=(ALL:ALL) ALL\n' "$ADMIN_USER" | write_file "/etc/sudoers.d/90-${ADMIN_USER}" 0440
if [[ $DRY_RUN == 0 ]]; then visudo -cf "/etc/sudoers.d/90-${ADMIN_USER}" >/dev/null || die "sudoers drop-in failed validation"; fi
KEY_INSTALLED=0
if [[ -n "$ADMIN_KEY" ]]; then
  home=$(getent passwd "$ADMIN_USER" | cut -d: -f6 || true); home=${home:-/home/$ADMIN_USER}
  auth="$home/.ssh/authorized_keys"
  if ! grep -qxF "$ADMIN_KEY" "$auth" 2>/dev/null; then
    { cat "$auth" 2>/dev/null || true; printf '%s\n' "$ADMIN_KEY"; } | write_file "$auth" 0600
  fi
  run chown -R "$ADMIN_USER:" "$home/.ssh"
  run chmod 0700 "$home/.ssh"
  KEY_INSTALLED=1
fi
if [[ $DRY_RUN == 0 ]] && passwd -S "$ADMIN_USER" 2>/dev/null | awk '{exit !($2 ~ /^(L|LK|NP)$/)}'; then
  if [[ $ASSUME_YES == 0 && -t 0 ]] && confirm "Set a password for ${ADMIN_USER} now (sudo asks for it)?"; then
    passwd "$ADMIN_USER"
  else
    warn "${ADMIN_USER} has no password yet: run 'passwd ${ADMIN_USER}' before relying on sudo"
  fi
fi

# ---------------------------------------------------------------- SSH
step "SSH hardening"
sshd_main=/etc/ssh/sshd_config
if [[ -f $sshd_main ]] && ! grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$sshd_main"; then
  { echo "Include /etc/ssh/sshd_config.d/*.conf"; cat "$sshd_main"; } | write_file "$sshd_main" 0600
fi
password_auth=$([[ $KEY_INSTALLED == 1 ]] && echo no || echo yes)
[[ $KEY_INSTALLED == 1 ]] || warn "no SSH key installed: password authentication stays enabled"
# 10- sorts before distribution/cloud-init drop-ins (sshd uses the first value it reads).
write_file /etc/ssh/sshd_config.d/10-baseline.conf 0600 <<EOF
# Managed by server-baseline.sh
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication ${password_auth}
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
AllowAgentForwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
if [[ $SSH_PORT != 22 && $OS_FAMILY == rhel ]] && command -v getenforce >/dev/null && [[ $(getenforce) != Disabled ]]; then
  run semanage port -a -t ssh_port_t -p tcp "$SSH_PORT" 2>/dev/null || run semanage port -m -t ssh_port_t -p tcp "$SSH_PORT"
fi
if [[ $DRY_RUN == 0 ]]; then
  if ! sshd -t 2>/tmp/sshd-test.err; then
    rm -f /etc/ssh/sshd_config.d/10-baseline.conf
    die "sshd rejected the configuration (removed it): $(cat /tmp/sshd-test.err)"
  fi
  if has_systemd; then
    ssh_unit=sshd
    systemctl cat ssh.service >/dev/null 2>&1 && ssh_unit=ssh   # Debian/Ubuntu name
    if systemctl is-active --quiet ssh.socket 2>/dev/null; then   # Ubuntu 22.10+: socket-activated sshd
      run systemctl daemon-reload; run systemctl restart ssh.socket
    else
      run systemctl reload "$ssh_unit" || run systemctl restart "$ssh_unit"
    fi
  fi
fi

# ---------------------------------------------------------------- firewall
if [[ $DO_FIREWALL == 1 ]]; then
  step "Firewall: SSH ${SSH_PORT}/tcp from ${MGMT_CIDR}"
  if [[ -n "${client_ip:-}" ]] && is_ipv4 "$client_ip" && [[ $MGMT_CIDR != 0.0.0.0/0 ]] \
     && ! same_subnet "$client_ip" "${MGMT_CIDR%/*}" "${MGMT_CIDR#*/}"; then
    die "your session (${client_ip}) is outside ${MGMT_CIDR}; this would lock you out"
  fi
  case $OS_FAMILY in
    debian)
      run ufw --force default deny incoming
      run ufw --force default allow outgoing
      if [[ $MGMT_CIDR == 0.0.0.0/0 ]]; then run ufw allow "${SSH_PORT}/tcp"
      else run ufw allow from "$MGMT_CIDR" to any port "$SSH_PORT" proto tcp; fi
      run ufw --force enable ;;
    rhel|suse)
      run systemctl enable --now firewalld
      if [[ $MGMT_CIDR == 0.0.0.0/0 ]]; then
        run firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
      else
        run firewall-cmd --permanent --remove-service=ssh
        run firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${MGMT_CIDR} port port=${SSH_PORT} protocol=tcp accept"
      fi
      run firewall-cmd --reload ;;
  esac
fi

# ---------------------------------------------------------------- automatic security updates
if [[ $DO_UPDATES == 1 ]]; then
  step "Automatic security updates"
  case $OS_FAMILY in
    debian)
      write_file /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
      if [[ -n "$AUTO_REBOOT" ]]; then
        write_file /etc/apt/apt.conf.d/52-baseline-reboot <<EOF
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "${AUTO_REBOOT}";
EOF
      fi ;;
    rhel)
      if [[ -f /etc/dnf/automatic.conf || $DRY_RUN == 1 ]]; then
        run sed -i -e 's/^upgrade_type.*/upgrade_type = security/' -e 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
        run systemctl enable --now dnf-automatic.timer
      else
        warn "dnf-automatic is not available here; configure updates manually"
      fi ;;
    suse)
      write_file /etc/systemd/system/zypper-security-patch.service <<'EOF'
[Unit]
Description=Install security patches (server-baseline)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/zypper --non-interactive patch --category security --auto-agree-with-licenses
EOF
      write_file /etc/systemd/system/zypper-security-patch.timer <<'EOF'
[Unit]
Description=Daily security patching (server-baseline)

[Timer]
OnCalendar=*-*-* 03:30
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF
      run systemctl daemon-reload
      run systemctl enable --now zypper-security-patch.timer ;;
  esac
fi

# ---------------------------------------------------------------- kernel hardening and audit
step "Kernel network hardening (sysctl) and auditd"
write_file /etc/sysctl.d/90-baseline.conf <<'EOF'
# Managed by server-baseline.sh (CIS-aligned network hardening)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.randomize_va_space = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
EOF
run sysctl --system >/dev/null || warn "some sysctl keys could not be applied (containers restrict them)"
if has_systemd; then run systemctl enable --now auditd || warn "auditd could not be started"; fi

step "Done"
ok "baseline applied to $(uname -n) (${OS_NAME})$([[ $DRY_RUN == 1 ]] && echo ' [dry-run: nothing changed]')"
if [[ $KEY_INSTALLED == 1 ]]; then
  info "test a NEW SSH session as ${ADMIN_USER} on port ${SSH_PORT} before closing this one"
fi
