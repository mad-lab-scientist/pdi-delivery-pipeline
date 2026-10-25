#!/usr/bin/env bash
# =============================================================================
# join-ad-domain.sh: join a Linux server to Active Directory with realmd + SSSD, on Debian/Ubuntu,
# RHEL/Rocky/Alma and SUSE.
#
#   sudo ./join-ad-domain.sh                                   interactive
#   sudo ./join-ad-domain.sh --domain corp.example.com --user joinadmin \
#        --ou "OU=Linux,OU=Servers,OU=Company,DC=corp,DC=example,DC=com" \
#        --allow-groups "SG-Linux-Admins,SG-App-Operators" --sudo-group SG-Linux-Admins
#   sudo ./join-ad-domain.sh --dry-run ...
#
# Pre-checks DNS (the _ldap._tcp.dc._msdcs SRV records) and clock skew against a DC before joining,
# installs the right packages per distribution, joins (realm prompts for the join account's password;
# it is never stored), then configures short user names, home directories created at first login,
# login restricted to the allowed AD groups and sudo for one AD group.
# =============================================================================
set -euo pipefail
# shellcheck source=SCRIPTDIR/../../linux/lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../../linux/lib/common.sh"

DOMAIN="" JOIN_USER="" OU="" ALLOW_GROUPS="" SUDO_GROUP=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --domain) DOMAIN=$2; shift 2 ;;
    --user) JOIN_USER=$2; shift 2 ;;
    --ou) OU=$2; shift 2 ;;
    --allow-groups) ALLOW_GROUPS=$2; shift 2 ;;
    --sudo-group) SUDO_GROUP=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '3,17p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ $DRY_RUN == 1 ]] || require_root
detect_os

is_account() { [[ $1 =~ ^[A-Za-z0-9._-]{1,64}$ ]]; }
ask DOMAIN "AD domain (FQDN, e.g. corp.example.com)" "" is_fqdn
DOMAIN=${DOMAIN,,}
ask JOIN_USER "Account allowed to join computers" "" is_account
if [[ -z $OU && $ASSUME_YES == 0 && -t 0 ]]; then read -r -p "Computer OU DN (blank for the default Computers container): " OU; fi
if [[ -z $ALLOW_GROUPS && $ASSUME_YES == 0 && -t 0 ]]; then read -r -p "AD groups allowed to log in (comma separated, blank = all domain users): " ALLOW_GROUPS; fi
if [[ -z $SUDO_GROUP && $ASSUME_YES == 0 && -t 0 ]]; then read -r -p "AD group granted sudo (blank for none): " SUDO_GROUP; fi

step "Packages"
case $OS_FAMILY in
  debian) run apt-get update -q
          pkg_install realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit krb5-user dnsutils chrony ;;
  rhel)   pkg_install realmd sssd oddjob oddjob-mkhomedir adcli samba-common-tools krb5-workstation authselect bind-utils chrony ;;
  suse)   pkg_install realmd sssd sssd-ad adcli samba-client krb5-client bind-utils chrony ;;
  *) die "unsupported distribution family: $OS_FAMILY" ;;
esac

step "Pre-checks for ${DOMAIN}"
if [[ $DRY_RUN == 0 ]]; then
  srv=$(dig +short -t SRV "_ldap._tcp.dc._msdcs.${DOMAIN}" 2>/dev/null | sort -n | awk '{print $4}' | sed 's/\.$//')
  [[ -n $srv ]] || die "DNS has no _ldap._tcp.dc._msdcs.${DOMAIN} SRV records: point /etc/resolv.conf (or netplan/nmcli DNS) at the AD DNS servers"
  dc=$(head -n 1 <<< "$srv")
  info "domain controllers: $(paste -sd' ' <<< "$srv")"
  if command -v chronyd >/dev/null; then
    offset=$(chronyd -Q "server ${dc} iburst" 2>&1 | awk '/offset/ {for (i=1;i<=NF;i++) if ($i == "offset") print $(i+1); exit}' || true)
    if [[ -n $offset ]] && awk -v o="$offset" 'BEGIN { exit !(o > 240 || o < -240) }'; then
      die "clock differs from ${dc} by ${offset}s; Kerberos allows 300s. Sync time (chrony) first."
    fi
    info "clock offset to ${dc}: ${offset:-unknown}s"
  fi
  realm discover "$DOMAIN" >/dev/null || die "realm discover ${DOMAIN} failed"
  if realm list --name-only 2>/dev/null | grep -qix "$DOMAIN"; then ok "already joined to ${DOMAIN}"; fi
fi

step "Join"
if ! realm list --name-only 2>/dev/null | grep -qix "$DOMAIN"; then
  args=(join --user="$JOIN_USER" --membership-software=adcli)
  [[ -n $OU ]] && args+=(--computer-ou="$OU")
  run realm "${args[@]}" "$DOMAIN"
fi

step "SSSD and PAM"
conf=/etc/sssd/sssd.conf
if [[ -f $conf || $DRY_RUN == 1 ]]; then
  {
    sed -e '/^use_fully_qualified_names/d' -e '/^fallback_homedir/d' -e '/^ad_gpo_access_control/d' "$conf" 2>/dev/null || true
  } | awk -v d="[domain/${DOMAIN}]" '{print} $0 == d {print "use_fully_qualified_names = False"; print "fallback_homedir = /home/%u"; print "ad_gpo_access_control = permissive"}' \
    | write_file "$conf" 0600
fi
case $OS_FAMILY in
  debian) run pam-auth-update --enable mkhomedir ;;
  rhel)   run authselect select sssd with-mkhomedir --force; run systemctl enable --now oddjobd ;;
  suse)   run pam-config --add --mkhomedir ;;
esac
if [[ -n $ALLOW_GROUPS ]]; then
  run realm deny --all
  IFS=',' read -r -a groups <<< "$ALLOW_GROUPS"
  for g in "${groups[@]}"; do run realm permit --groups "$(sed 's/^ *//; s/ *$//' <<< "$g")"; done
fi
if [[ -n $SUDO_GROUP ]]; then
  # sudoers needs spaces in group names escaped; % marks a group.
  printf '%%%s ALL=(ALL:ALL) ALL\n' "${SUDO_GROUP// /\\ }" | write_file "/etc/sudoers.d/60-ad-${SUDO_GROUP// /-}" 0440
  [[ $DRY_RUN == 1 ]] || visudo -cf "/etc/sudoers.d/60-ad-${SUDO_GROUP// /-}" >/dev/null || die "sudoers validation failed"
fi
run systemctl restart sssd

step "Verify"
if [[ $DRY_RUN == 0 ]]; then
  realm list "$DOMAIN" | sed 's/^/  /'
  if id "$JOIN_USER" >/dev/null 2>&1; then
    ok "AD lookup works: $(id "$JOIN_USER")"
  else
    warn "could not resolve ${JOIN_USER} yet (sssd may need a minute)"
  fi
fi
ok "done: log in with your AD user name (no domain suffix)"
