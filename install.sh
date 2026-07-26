#!/usr/bin/env bash
set -Eeuo pipefail

RAW_URL="https://raw.githubusercontent.com/yeasinulhoquetuhin/TDZ-TG-PAYLOAD-INJ/master/tdzp"
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
TMP_FILE=""

if [[ -t 1 ]]; then
    RESET=$'\033[0m'; BOLD=$'\033[1m'; RED=$'\033[38;5;196m'; GREEN=$'\033[38;5;46m'
    YELLOW=$'\033[38;5;226m'; CYAN=$'\033[38;2;0;212;255m'; GRAY=$'\033[38;5;245m'
else
    RESET=''; BOLD=''; RED=''; GREEN=''; YELLOW=''; CYAN=''; GRAY=''
fi

BOX_WIDTH=58
repeat_char() { local char=$1 count=$2 out; printf -v out '%*s' "$count" ''; printf '%s' "${out// /$char}"; }
center_line() {
    local text=$1 color=${2:-$CYAN} len left right
    len=${#text}; left=$(( (BOX_WIDTH-len)/2 )); right=$(( BOX_WIDTH-len-left ))
    printf '  %b║%*s%b%s%b%*s%b║%b\n' "$CYAN" "$left" '' "$color" "$text" "$RESET" "$right" '' "$CYAN" "$RESET"
}
banner() {
    [[ -t 1 ]] && clear || true
    echo
    printf '  %b╔%s╗%b\n' "$CYAN" "$(repeat_char '═' "$BOX_WIDTH")" "$RESET"
    center_line 'TDZ PAYLOAD PROXY' "${BOLD}${CYAN}"
    center_line 'Powered By: t.me/TuhinBroh' "$GRAY"
    printf '  %b╚%s╝%b\n' "$CYAN" "$(repeat_char '═' "$BOX_WIDTH")" "$RESET"
}
step() {
    local number=$1 total=$2 label=$3; shift 3
    printf '  [%s/%s] %-34s' "$number" "$total" "$label"
    if "$@" >/dev/null 2>&1; then printf '%bDONE%b\n' "$GREEN" "$RESET"; else printf '%bFAILED%b\n' "$RED" "$RESET"; return 1; fi
}
fail() { printf '\n  %b✗%b %s\n' "$RED" "$RESET" "$1"; exit 1; }
valid_port() { [[ ${1:-} =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
cleanup() { [[ -n "$TMP_FILE" ]] && rm -f "$TMP_FILE"; }
trap cleanup EXIT

(( EUID == 0 )) || fail 'Run as root: sudo bash install.sh'
command -v apt-get >/dev/null 2>&1 || fail 'Ubuntu or Debian is required.'

banner
echo
step 1 3 'Preparing required packages' bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -y && apt-get install -y python3 curl iproute2 ca-certificates'

TMP_FILE=$(mktemp)
if [[ -r "$SELF_DIR/tdzp" ]]; then
    step 2 3 'Installing TDZP command' install -m 0755 "$SELF_DIR/tdzp" /usr/local/bin/tdzp
else
    curl -fsSL --retry 3 --connect-timeout 15 "$RAW_URL" -o "$TMP_FILE" || fail 'Could not download tdzp.'
    bash -n "$TMP_FILE" || fail 'Downloaded file is invalid.'
    step 2 3 'Installing TDZP command' install -m 0755 "$TMP_FILE" /usr/local/bin/tdzp
fi
step 3 3 'Checking installed command' bash -n /usr/local/bin/tdzp

echo
while true; do
    read -r -p '  Select Public Port: ' PUBLIC_PORT
    valid_port "$PUBLIC_PORT" && break
    printf '  %bInvalid port. Use 1-65535.%b\n' "$RED" "$RESET"
done
while true; do
    read -r -p '  Select Backend Port: ' BACKEND_PORT
    valid_port "$BACKEND_PORT" || { printf '  %bInvalid port. Use 1-65535.%b\n' "$RED" "$RESET"; continue; }
    [[ "$BACKEND_PORT" != "$PUBLIC_PORT" ]] || { printf '  %bPorts must be different.%b\n' "$RED" "$RESET"; continue; }
    break
done

echo
printf '  Configuring proxy service... '
if /usr/local/bin/tdzp --setup "$PUBLIC_PORT" "$BACKEND_PORT" >/dev/null 2>&1; then
    printf '%bDONE%b\n' "$GREEN" "$RESET"
else
    printf '%bFAILED%b\n' "$RED" "$RESET"
    journalctl -u tdzp.service -n 15 --no-pager 2>/dev/null || true
    exit 1
fi

echo
printf '  %b✓ TDZ Payload Proxy installed successfully.%b\n' "$GREEN" "$RESET"
printf '  Public Port : %b%s%b\n' "$CYAN" "$PUBLIC_PORT" "$RESET"
printf '  Backend Port: %b%s%b\n' "$CYAN" "$BACKEND_PORT" "$RESET"
printf '  Manager     : %btdzp%b\n\n' "$YELLOW" "$RESET"
