#!/usr/bin/env bash
set -Eeuo pipefail

RAW_URL="https://raw.githubusercontent.com/yeasinulhoquetuhin/TDZ-TG-PAYLOAD-INJ/master/tdzp"
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
TMP_FILE=""
LOG_FILE=""

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
    center_line 'TDZ PAYLOAD PROXY SETUP' "${BOLD}${CYAN}"
    center_line 'Powered By: t.me/TuhinBroh' "$GRAY"
    printf '  %b╚%s╝%b\n' "$CYAN" "$(repeat_char '═' "$BOX_WIDTH")" "$RESET"
}
fail() {
    printf '\n  %b✗%b %s\n' "$RED" "$RESET" "$1"
    [[ -r "$LOG_FILE" ]] && { echo; tail -n 15 "$LOG_FILE" 2>/dev/null || true; }
    exit 1
}
valid_port() { [[ ${1:-} =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
cleanup() { [[ -n "$TMP_FILE" ]] && rm -f "$TMP_FILE"; [[ -n "$LOG_FILE" ]] && rm -f "$LOG_FILE"; }
trap cleanup EXIT
spinner_step() {
    local number=$1 total=$2 label=$3; shift 3
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0 pid status
    : > "$LOG_FILE"
    "$@" >"$LOG_FILE" 2>&1 & pid=$!
    if [[ -t 1 ]]; then
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  [%s/%s] %b%s%b %-32s' "$number" "$total" "$CYAN" "${frames[$i]}" "$RESET" "$label"
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.08
        done
    fi
    if wait "$pid"; then status=0; else status=$?; fi
    if (( status == 0 )); then
        printf '\r  [%s/%s] %b✓%b %-32s %bDONE%b\n' "$number" "$total" "$GREEN" "$RESET" "$label" "$GREEN" "$RESET"
    else
        printf '\r  [%s/%s] %b✗%b %-32s %bFAILED%b\n' "$number" "$total" "$RED" "$RESET" "$label" "$RED" "$RESET"
        return "$status"
    fi
}
install_tdzp() {
    if [[ -r "$SELF_DIR/tdzp" ]]; then
        install -m 0755 "$SELF_DIR/tdzp" /usr/local/bin/tdzp
    else
        curl -fsSL --retry 3 --connect-timeout 15 "$RAW_URL" -o "$TMP_FILE"
        bash -n "$TMP_FILE"
        install -m 0755 "$TMP_FILE" /usr/local/bin/tdzp
    fi
}
prepare_tdzp() { /usr/local/bin/tdzp --migrate; }
check_tdzp() { bash -n /usr/local/bin/tdzp && /usr/local/bin/tdzp --version >/dev/null; }

(( EUID == 0 )) || fail 'Run as root: sudo bash install.sh'
command -v apt-get >/dev/null 2>&1 || fail 'Ubuntu or Debian is required.'
TMP_FILE=$(mktemp)
LOG_FILE=$(mktemp)

banner
echo
spinner_step 1 4 'Preparing required packages' bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -y && apt-get install -y python3 curl iproute2 ca-certificates' || fail 'Package installation failed.'
spinner_step 2 4 'Installing TDZP command' install_tdzp || fail 'Could not install tdzp.'
spinner_step 3 4 'Preparing proxy services' prepare_tdzp || fail 'Could not prepare proxy services.'
spinner_step 4 4 'Checking installed command' check_tdzp || fail 'Installed command is invalid.'

if /usr/local/bin/tdzp --has-instances; then
    COUNT=$(/usr/local/bin/tdzp --count)
    echo
    printf '  %b✓ TDZ Payload Proxy is ready.%b\n' "$GREEN" "$RESET"
    printf '  Existing Proxies: %b%s%b\n' "$CYAN" "$COUNT" "$RESET"
    printf '  Manager         : %btdzp%b\n\n' "$YELLOW" "$RESET"
    exit 0
fi

echo
while true; do
    read -r -p '  Choose Public Port: ' PUBLIC_PORT
    valid_port "$PUBLIC_PORT" && break
    printf '  %bInvalid port. Use 1-65535.%b\n' "$RED" "$RESET"
done
while true; do
    read -r -p '  Choose Backend Port: ' BACKEND_PORT
    valid_port "$BACKEND_PORT" || { printf '  %bInvalid port. Use 1-65535.%b\n' "$RED" "$RESET"; continue; }
    [[ "$BACKEND_PORT" != "$PUBLIC_PORT" ]] || { printf '  %bPorts must be different.%b\n' "$RED" "$RESET"; continue; }
    break
done

echo
printf '  Creating default proxy... '
if PROXY_ID=$(/usr/local/bin/tdzp --create "$PUBLIC_PORT" "$BACKEND_PORT"); then
    printf '%bDONE%b\n' "$GREEN" "$RESET"
else
    printf '%bFAILED%b\n' "$RED" "$RESET"
    exit 1
fi

echo
printf '  %b✓ TDZ Payload Proxy installed successfully.%b\n' "$GREEN" "$RESET"
printf '  Proxy ID    : %b#%s%b\n' "$CYAN" "$PROXY_ID" "$RESET"
printf '  Public Port : %b%s%b\n' "$CYAN" "$PUBLIC_PORT" "$RESET"
printf '  Backend Port: %b%s%b\n' "$CYAN" "$BACKEND_PORT" "$RESET"
printf '  Manager     : %btdzp%b\n\n' "$YELLOW" "$RESET"
