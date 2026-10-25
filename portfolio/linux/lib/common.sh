#!/usr/bin/env bash
# Shared helpers for the linux/ scripts: logging, OS detection, prompts, input validation and dry-run.
# Source it:  source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

[[ -n "${_PDI_COMMON_LOADED:-}" ]] && return 0
_PDI_COMMON_LOADED=1

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

if [[ -t 1 ]]; then
  _C_RED=$'\e[31m'; _C_YEL=$'\e[33m'; _C_GRN=$'\e[32m'; _C_BLU=$'\e[34m'; _C_OFF=$'\e[0m'
else
  _C_RED=""; _C_YEL=""; _C_GRN=""; _C_BLU=""; _C_OFF=""
fi

info() { printf '%s[*]%s %s\n' "$_C_BLU" "$_C_OFF" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$_C_GRN" "$_C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$_C_YEL" "$_C_OFF" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$_C_RED" "$_C_OFF" "$*" >&2; exit 1; }
step() { printf '\n%s== %s%s\n' "$_C_BLU" "$*" "$_C_OFF"; }

require_root() { [[ $EUID -eq 0 ]] || die "run as root (sudo $0 ...)"; }

# run CMD...: execute, or only print it when DRY_RUN=1
run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# write_file PATH MODE < content: atomic write with a timestamped backup of any existing file
write_file() {
  local path=$1 mode=${2:-0644} tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '  [dry-run] would write %s:\n' "$path"
    sed 's/^/    | /' "$tmp"
    rm -f "$tmp"
    return 0
  fi
  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    return 0
  fi
  [[ -f "$path" ]] && cp -p "$path" "$path.bak.$(date +%Y%m%d%H%M%S)"
  install -D -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

# detect_os: sets OS_ID, OS_VERSION, OS_NAME, OS_FAMILY (debian|rhel|suse|alpine|arch) and PKG
detect_os() {
  [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
  # Subshell: sourcing os-release directly would overwrite variables such as NAME and VERSION.
  OS_ID=$(. /etc/os-release && echo "${ID:-unknown}")
  OS_VERSION=$(. /etc/os-release && echo "${VERSION_ID:-}")
  OS_NAME=$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")
  local like
  like=$(. /etc/os-release && echo "${ID:-} ${ID_LIKE:-}")
  case " $like " in
    *" debian "*|*" ubuntu "*) OS_FAMILY=debian; PKG=apt ;;
    *" rhel "*|*" fedora "*|*" centos "*) OS_FAMILY=rhel; PKG=$(command -v dnf >/dev/null && echo dnf || echo yum) ;;
    *" suse "*|*" sles "*|*" opensuse "*) OS_FAMILY=suse; PKG=zypper ;;
    *" alpine "*) OS_FAMILY=alpine; PKG=apk ;;
    *" arch "*) OS_FAMILY=arch; PKG=pacman ;;
    *) die "unsupported distribution: $like" ;;
  esac
  export OS_ID OS_VERSION OS_NAME OS_FAMILY PKG
}

# pkg_install PACKAGE...: install with the native package manager, non-interactively
pkg_install() {
  case "$PKG" in
    apt) run env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" ;;
    dnf|yum) run "$PKG" install -y -q "$@" ;;
    zypper) run zypper --non-interactive --quiet install --no-recommends "$@" ;;
    apk) run apk add --no-cache "$@" ;;
    pacman) run pacman -S --noconfirm --needed "$@" ;;
  esac
}

has_systemd() { [[ -d /run/systemd/system ]]; }

# ---------------------------------------------------------------- validation
is_ipv4() {
  local ip=$1 octet
  [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for octet in "${BASH_REMATCH[@]:1}"; do
    (( 10#$octet <= 255 )) || return 1
  done
}
is_cidr() {
  local ip=${1%/*} prefix=${1#*/}
  [[ $1 == */* ]] && is_ipv4 "$ip" && [[ $prefix =~ ^[0-9]{1,2}$ ]] && (( prefix <= 32 ))
}
is_hostname() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; }
is_fqdn() { [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }
is_port() { [[ $1 =~ ^[0-9]{1,5}$ ]] && (( $1 >= 1 && $1 <= 65535 )); }

ip_to_int() { local IFS=. a b c d; read -r a b c d <<< "$1"; echo $(( (a << 24) | (b << 16) | (c << 8) | d )); }
int_to_ip() { echo "$(( ($1 >> 24) & 255 )).$(( ($1 >> 16) & 255 )).$(( ($1 >> 8) & 255 )).$(( $1 & 255 ))"; }
prefix_to_mask() { int_to_ip $(( (0xFFFFFFFF << (32 - $1)) & 0xFFFFFFFF )); }

# same_subnet IP_A IP_B PREFIX
same_subnet() {
  local mask=$(( (0xFFFFFFFF << (32 - $3)) & 0xFFFFFFFF ))
  (( ( $(ip_to_int "$1") & mask ) == ( $(ip_to_int "$2") & mask ) ))
}

# ---------------------------------------------------------------- prompts
# ask VAR "Question" [default] [validator]: keeps a value already set (flag or env), else prompts until valid
ask() {
  local __var=$1 question=$2 default=${3:-} validator=${4:-} answer
  if [[ -n "${!__var:-}" ]]; then
    if [[ -n "$validator" ]] && ! "$validator" "${!__var}"; then die "invalid value for $__var: ${!__var}"; fi
    return 0
  fi
  if [[ "$ASSUME_YES" == 1 || ! -t 0 ]]; then
    [[ -n "$default" ]] || die "$__var is required (set it with a flag in non-interactive mode)"
    printf -v "$__var" '%s' "$default"
    return 0
  fi
  while true; do
    read -r -p "$question${default:+ [$default]}: " answer
    answer=${answer:-$default}
    if [[ -z "$answer" ]]; then warn "a value is required"; continue; fi
    if [[ -n "$validator" ]] && ! "$validator" "$answer"; then warn "'$answer' is not valid"; continue; fi
    printf -v "$__var" '%s' "$answer"
    return 0
  done
}

# confirm "Question": true on yes (always true with ASSUME_YES=1)
confirm() {
  [[ "$ASSUME_YES" == 1 ]] && return 0
  local reply
  read -r -p "$1 [y/N]: " reply
  [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}
