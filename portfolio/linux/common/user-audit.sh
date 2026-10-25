#!/usr/bin/env bash
# =============================================================================
# user-audit.sh: local account and privilege review (read-only), for access reviews and audits.
#
#   sudo ./user-audit.sh                 report to the screen
#   sudo ./user-audit.sh > audit-$(uname -n)-$(date +%F).txt
#
# Reports: extra UID 0 accounts, accounts with empty passwords, interactive accounts with password
# age and expiry, sudo/wheel membership and NOPASSWD rules, SSH authorized keys (type, size and
# fingerprint; weak keys flagged), last logins, and home directories other users can read.
# Exit codes: 0 no findings, 1 warnings, 2 critical findings.
# =============================================================================
set -uo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
require_root
detect_os

STATUS=0
finding() { (( $1 > STATUS )) && STATUS=$1; printf '  %s %s\n' "$([[ $1 == 2 ]] && echo '[CRITICAL]' || echo '[WARNING] ')" "$2"; }
today=$(( $(date +%s) / 86400 ))

step "Host $(uname -n) (${OS_NAME}), $(date '+%F %T %Z')"

step "Privileged identities"
while IFS=: read -r user _ uid _; do
  [[ $uid == 0 && $user != root ]] && finding 2 "UID 0 account besides root: ${user}"
done < /etc/passwd
while IFS=: read -r user hash _; do
  [[ -z $hash ]] && finding 2 "account with an EMPTY password: ${user}"
done < /etc/shadow
for group in sudo wheel admin; do
  members=$(getent group "$group" | cut -d: -f4)
  [[ -n $members ]] && printf '  group %-6s %s\n' "$group" "${members//,/, }"
done
while IFS= read -r line; do
  finding 1 "NOPASSWD sudo rule: ${line}"
done < <(grep -hsE '^[[:space:]]*[^#].*NOPASSWD' /etc/sudoers /etc/sudoers.d/* 2>/dev/null)

step "Interactive accounts"
printf '  %-16s %-6s %-22s %-12s %-10s %s\n' USER UID SHELL "PW CHANGED" "MAX DAYS" "LAST LOGIN"
while IFS=: read -r user _ uid _ _ home shell; do
  [[ $shell =~ (nologin|false|sync|shutdown|halt)$ ]] && continue
  (( uid == 0 || uid >= 1000 )) || continue
  IFS=: read -r _ hash lastchg _ max _ < <(grep "^${user}:" /etc/shadow)
  changed=$([[ $lastchg =~ ^[0-9]+$ ]] && date -d "@$(( lastchg * 86400 ))" +%F || echo never)
  last=$(lastlog -u "$user" 2>/dev/null | awk 'NR == 2 { if ($0 ~ /Never logged in/) print "never"; else print $(NF-5), $(NF-4), $(NF-3), $NF }')
  [[ -z $last ]] && last=$(last -n 1 -w "$user" 2>/dev/null | awk 'NR == 1 && NF > 3 {print $4, $5, $6, $7}')
  printf '  %-16s %-6s %-22s %-12s %-10s %s\n' "$user" "$uid" "$shell" "$changed" "${max:-}" "${last:-unknown}"
  [[ $hash =~ ^[!*] ]] || { [[ ${max:-99999} =~ ^[0-9]+$ ]] && (( ${max:-99999} > 365 )) && [[ $user != root ]] \
      && finding 1 "${user}: password never expires (max ${max:-unset} days)"; }
  if [[ $lastchg =~ ^[0-9]+$ ]] && [[ ${max:-} =~ ^[0-9]+$ ]] && (( max < 99999 && lastchg + max < today )); then
    finding 1 "${user}: password expired $(( today - lastchg - max )) day(s) ago"
  fi
  if [[ -d $home ]]; then
    perm=$(stat -c %a "$home")
    (( 8#$perm & 8#007 )) && finding 1 "${user}: home ${home} is accessible by other users (mode ${perm})"
  fi
done < /etc/passwd

step "SSH authorized keys"
while IFS=: read -r user _ _ _ _ home _; do
  for file in "$home/.ssh/authorized_keys" "$home/.ssh/authorized_keys2"; do
    [[ -f $file ]] || continue
    while IFS= read -r key; do
      [[ -z $key || $key == \#* ]] && continue
      info_line=$(ssh-keygen -lf - <<< "$key" 2>/dev/null) || { finding 1 "${user}: unparsable key line in ${file}"; continue; }
      read -r bits fp _ <<< "$info_line"
      type=${info_line##* }
      printf '  %-14s %-9s %5s %s\n' "$user" "$type" "$bits" "$fp"
      [[ $type == "(DSA)" ]] && finding 2 "${user}: DSA key (broken, disabled since OpenSSH 7.0) in ${file}"
      [[ $type == "(RSA)" ]] && (( bits < 2048 )) && finding 2 "${user}: ${bits}-bit RSA key in ${file}"
      [[ $user == root ]] && finding 1 "root has an authorized key (${fp}); prefer named accounts with sudo"
    done < "$file"
  done
done < /etc/passwd

step "Result"
case $STATUS in 0) ok "no findings" ;; 1) warn "warnings found" ;; 2) warn "CRITICAL findings" ;; esac
exit "$STATUS"
