#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.1"
REPO_RAW_URL="${TDZP_REPO_RAW_URL:-https://raw.githubusercontent.com/yeasinulhoquetuhin/TDZ-TG-PAYLOAD-INJ/master}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
CONFIG_DIR="/etc/tdz-payload"
CONFIG_FILE="$CONFIG_DIR/tdzp.conf"
FIREWALL_STATE="$CONFIG_DIR/firewall.conf"
LIB_DIR="/usr/local/lib/tdz-payload"
RUNTIME_BIN="$LIB_DIR/tdz_payload_proxy.py"
MANAGER_BIN="/usr/local/bin/tdzp"
SERVICE_NAME="tdz-payload.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
SYSCTL_FILE="/etc/sysctl.d/99-tdz-payload.conf"
APP_USER="tdzpayload"
APP_GROUP="tdzpayload"
TMP_DIR=""

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[38;5;196m'; C_GREEN=$'\033[38;5;46m'
    C_YELLOW=$'\033[38;5;226m'; C_NAVY=$'\033[38;5;39m'; C_BLUE=$'\033[38;2;0;212;255m'
    C_CYAN=$C_BLUE; C_WHITE=$'\033[38;5;255m'; C_GRAY=$'\033[38;5;245m'; C_CHOICE=$C_CYAN
else
    C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_NAVY=''; C_BLUE=''
    C_CYAN=''; C_WHITE=''; C_GRAY=''; C_CHOICE=''
fi
C_TITLE=$C_NAVY; C_PROMPT=$C_BLUE
TDZ_BOX_WIDTH=58
if [[ -t 1 ]]; then
    cols=${COLUMNS:-}; [[ "$cols" =~ ^[0-9]+$ ]] || cols=$(tput cols 2>/dev/null || printf '80')
    (( cols - 4 < TDZ_BOX_WIDTH )) && TDZ_BOX_WIDTH=$((cols - 4)); (( TDZ_BOX_WIDTH < 38 )) && TDZ_BOX_WIDTH=38
fi
strip_ansi() { printf '%b' "$1" | sed -E $'s/\x1B\[[0-9;]*[mK]//g'; }
text_width() { local text; text=$(strip_ansi "$1"); printf '%s' "${#text}"; }
fit_text() { local text=$1 max=$2 plain; plain=$(strip_ansi "$text"); if (( ${#plain} <= max )); then printf '%s' "$text"; else printf '%s...' "${plain:0:max-3}"; fi; }
line_fill() { local count=$1 out; printf -v out '%*s' "$count" ''; printf '%s' "${out// /─}"; }
banner_fill() { local count=$1 out; printf -v out '%*s' "$count" ''; printf '%s' "${out// /═}"; }
tdz_banner_top() { printf '  %b╔%s╗%b\n' "$C_CYAN" "$(banner_fill "$TDZ_BOX_WIDTH")" "$C_RESET"; }
tdz_banner_bot() { printf '  %b╚%s╝%b\n' "$C_CYAN" "$(banner_fill "$TDZ_BOX_WIDTH")" "$C_RESET"; }
tdz_center_row() {
    local plain=$1 styled=$2 width left right
    plain=$(fit_text "$plain" "$TDZ_BOX_WIDTH")
    width=${#plain}
    left=$(( (TDZ_BOX_WIDTH - width) / 2 )); (( left < 0 )) && left=0
    right=$(( TDZ_BOX_WIDTH - width - left )); (( right < 0 )) && right=0
    printf '  %b║%b%*s%b%s%b%*s%b║%b\n' \
        "$C_CYAN" "$C_RESET" "$left" '' "$C_RESET" "$styled" "$C_RESET" "$right" '' "$C_CYAN" "$C_RESET"
}
tdz_box_top() { printf '  %b┌%s┐%b\n' "${1:-$C_TITLE}" "$(line_fill "$TDZ_BOX_WIDTH")" "$C_RESET"; }
tdz_box_divider() { printf '  %b├%s┤%b\n' "${1:-$C_TITLE}" "$(line_fill "$TDZ_BOX_WIDTH")" "$C_RESET"; }
tdz_box_bot() { printf '  %b└%s┘%b\n' "${1:-$C_TITLE}" "$(line_fill "$TDZ_BOX_WIDTH")" "$C_RESET"; }
tdz_row() { local text=$1 color=${2:-$C_TITLE} width pad; text=$(fit_text "$text" $((TDZ_BOX_WIDTH - 2))); width=$(text_width "$text"); pad=$((TDZ_BOX_WIDTH - width - 1)); (( pad < 1 )) && pad=1; printf '  %b│%b %s%*s%b│%b\n' "$color" "$C_RESET" "$text" "$pad" '' "$color" "$C_RESET"; }
tdz_box_header() { tdz_row "${C_BOLD}${C_GREEN}▶ $(fit_text "$1" $((TDZ_BOX_WIDTH - 5)))${C_RESET}" "${2:-$C_TITLE}"; }
tdz_message() { local kind=${1^^} msg=$2 color label; case "$kind" in OK|SUCCESS) color=$C_GREEN; label=OK;; INFO) color=$C_BLUE; label=INFO;; WARNING|WARN) color=$C_YELLOW; label=WARNING;; *) color=$C_RED; label=ERROR;; esac; printf '  %b[%s]%b %s\n' "$color" "$label" "$C_RESET" "$msg"; }
show_banner() {
    [[ -t 1 ]] && clear || true
    echo
    tdz_banner_top
    tdz_center_row "TDZ PAYLOAD PROXY" "${C_BOLD}${C_CYAN}TDZ PAYLOAD PROXY${C_RESET}"
    tdz_center_row "Powered By: t.me/TuhinBroh" "${C_GRAY}Powered By: t.me/TuhinBroh${C_RESET}"
    tdz_banner_bot
}

progress_run() {
    local current=$1 total=$2 label=$3; shift 3
    local label_width=35 pid='' i
    if [[ -t 1 ]]; then
        ( local n=0; local -a spin=('◐' '◓' '◑' '◒'); while true; do printf '\r\033[2K  %b[%s/%s]%b %-*s %b%s%b' "$C_CYAN" "$current" "$total" "$C_RESET" "$label_width" "$label" "$C_CYAN" "${spin[$n]}" "$C_RESET"; n=$(((n+1)%4)); sleep 0.1; done ) & pid=$!
    else
        printf '  [%s/%s] %-*s' "$current" "$total" "$label_width" "$label"
    fi
    if "$@" >/dev/null 2>&1; then
        [[ -n "$pid" ]] && { kill "$pid" >/dev/null 2>&1 || true; wait "$pid" 2>/dev/null || true; printf '\r\033[2K'; }
        printf '  %b✓%b %s\n' "$C_GREEN" "$C_RESET" "$label"; return 0
    fi
    [[ -n "$pid" ]] && { kill "$pid" >/dev/null 2>&1 || true; wait "$pid" 2>/dev/null || true; printf '\r\033[2K'; }
    printf '  %b✗%b %s\n' "$C_RED" "$C_RESET" "$label"; return 1
}

cleanup() { [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT
fatal() { tdz_message error "$1"; exit 1; }
require_root() { (( EUID == 0 )) || fatal "Run the installer as root."; }
validate_port() { [[ ${1:-} =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
port_is_listening() { command -v ss >/dev/null 2>&1 && ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[:.]|\\])$1$"; }
config_value() { local key=$1; awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$CONFIG_FILE" 2>/dev/null; }

fetch_component() {
    local name=$1 destination=$2 source_file="$SCRIPT_DIR/$name"
    if [[ -r "$source_file" ]]; then
        cp -f "$source_file" "$destination"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 15 "$REPO_RAW_URL/$name" -o "$destination"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=15 --tries=3 "$REPO_RAW_URL/$name" -O "$destination"
    else
        return 1
    fi
}

install_requirements() {
    command -v apt-get >/dev/null 2>&1 || return 1
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || return 1
    apt-get install -y python3 iproute2 ca-certificates curl || return 1
}
create_identity() {
    getent group "$APP_GROUP" >/dev/null 2>&1 || groupadd --system "$APP_GROUP" || return 1
    local nologin_shell
    nologin_shell=$(command -v nologin 2>/dev/null || printf '/usr/sbin/nologin')
    id "$APP_USER" >/dev/null 2>&1 || useradd --system --gid "$APP_GROUP" --home-dir /nonexistent --shell "$nologin_shell" "$APP_USER" || return 1
}
install_engine() {
    create_identity || return 1
    install -d -m 0755 "$LIB_DIR" || return 1
    install -d -m 0750 -o root -g "$APP_GROUP" "$CONFIG_DIR" || return 1
    fetch_component tdz_payload_proxy.py "$TMP_DIR/tdz_payload_proxy.py" || return 1
    fetch_component manager.sh "$TMP_DIR/manager.sh" || return 1
    install -m 0755 "$TMP_DIR/tdz_payload_proxy.py" "$RUNTIME_BIN" || return 1
    install -m 0755 "$TMP_DIR/manager.sh" "$MANAGER_BIN" || return 1
    ln -sfn "$MANAGER_BIN" /usr/local/bin/TDZP || return 1
    ln -sfn "$MANAGER_BIN" /usr/local/bin/tdZp || return 1
    write_service || return 1
}
write_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=TDZ Payload Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
EnvironmentFile=$CONFIG_FILE
ExecStart=/usr/bin/python3 $RUNTIME_BIN --bind 0.0.0.0 --public-port \${PUBLIC_PORT} --target-host 127.0.0.1 --target-port \${BACKEND_PORT}
Restart=always
RestartSec=2
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 0644 "$SERVICE_FILE" || return 1
    systemctl daemon-reload || return 1
}
apply_speed_boost() {
    local bbr_line=''
    modprobe tcp_bbr >/dev/null 2>&1 || true
    if sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        bbr_line='net.ipv4.tcp_congestion_control = bbr'
    fi
    cat > "$SYSCTL_FILE" <<EOF
# TDZ Payload Proxy - managed network tuning
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
$bbr_line
EOF
    sed -i '/^[[:space:]]*$/d' "$SYSCTL_FILE"
    sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true
}
validate_components() {
    bash -n "$MANAGER_BIN" || return 1
    python3 -m py_compile "$RUNTIME_BIN" || return 1
    [[ -x "$MANAGER_BIN" && -x "$RUNTIME_BIN" && -s "$SERVICE_FILE" ]] || return 1
}
write_config() {
    local public=$1 backend=$2 tmp
    tmp=$(mktemp "$CONFIG_DIR/.tdzp.XXXXXX")
    printf 'PUBLIC_PORT=%s\nBACKEND_PORT=%s\n' "$public" "$backend" > "$tmp" || return 1
    chmod 0640 "$tmp" || return 1
    chown root:"$APP_GROUP" "$tmp" || return 1
    mv -f "$tmp" "$CONFIG_FILE" || return 1
}
read_state_value() { local file=$1 key=$2; awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$file" 2>/dev/null; }
write_firewall_state() { printf 'METHOD=%s\nPORT=%s\nADDED=%s\n' "$1" "$2" "$3" > "$FIREWALL_STATE"; chmod 0600 "$FIREWALL_STATE"; }
firewall_open() {
    local port=$1 method=none added=0
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
        method=ufw
        if ! ufw status 2>/dev/null | grep -Eq "^${port}/tcp[[:space:]]+ALLOW"; then ufw allow "$port/tcp" comment 'TDZ Payload Proxy' >/dev/null; added=1; fi
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        method=firewalld
        if ! firewall-cmd --permanent --query-port="${port}/tcp" >/dev/null 2>&1; then firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null; firewall-cmd --reload >/dev/null; added=1; fi
    elif command -v iptables >/dev/null 2>&1; then
        method=iptables
        if ! iptables -C INPUT -p tcp --dport "$port" -m comment --comment TDZ_PAYLOAD_PROXY -j ACCEPT >/dev/null 2>&1; then iptables -I INPUT -p tcp --dport "$port" -m comment --comment TDZ_PAYLOAD_PROXY -j ACCEPT; added=1; fi
    fi
    write_firewall_state "$method" "$port" "$added"
}
firewall_close_file() {
    local file=$1 method port added
    [[ -r "$file" ]] || return 0
    method=$(read_state_value "$file" METHOD); port=$(read_state_value "$file" PORT); added=$(read_state_value "$file" ADDED)
    [[ "$added" == 1 ]] || return 0
    case "$method" in
        ufw) ufw --force delete allow "$port/tcp" >/dev/null 2>&1 || true ;;
        firewalld) firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || true; firewall-cmd --reload >/dev/null 2>&1 || true ;;
        iptables) iptables -D INPUT -p tcp --dport "$port" -m comment --comment TDZ_PAYLOAD_PROXY -j ACCEPT >/dev/null 2>&1 || true ;;
    esac
}
prompt_port() {
    local label=$1 default=$2 other=$3 value
    while true; do
        read -r -p "$(printf '%b' "${C_PROMPT}  ${label} [${default}]: ${C_RESET}")" value
        value=${value:-$default}
        if ! validate_port "$value"; then tdz_message error "Enter a port between 1 and 65535."
        elif [[ "$value" == "$other" ]]; then tdz_message error "Public and backend ports must be different."
        else REPLY=$value; return 0; fi
    done
}
wait_for_service() {
    local port=$1 i
    for ((i=0; i<25; i++)); do
        if systemctl is-active --quiet "$SERVICE_NAME" && port_is_listening "$port"; then return 0; fi
        sleep 0.2
    done
    return 1
}

main() {
    require_root
    command -v systemctl >/dev/null 2>&1 || fatal "systemd is required."
    TMP_DIR=$(mktemp -d)
    show_banner
    tdz_box_top; tdz_box_header "INSTALLATION PROGRESS"; tdz_box_bot; echo
    progress_run 1 4 "Installing requirements" install_requirements || fatal "Package installation failed."
    progress_run 2 4 "Setting up proxy engine" install_engine || fatal "Could not install proxy components."
    progress_run 3 4 "Applying Speed Boost" apply_speed_boost || fatal "Network tuning failed."
    progress_run 4 4 "Validating components" validate_components || fatal "Component validation failed."

    local old_public='' old_backend='' public_default=8080 backend_default=22
    [[ -r "$CONFIG_FILE" ]] && old_public=$(config_value PUBLIC_PORT) && old_backend=$(config_value BACKEND_PORT)
    validate_port "$old_public" && public_default=$old_public || true
    validate_port "$old_backend" && backend_default=$old_backend || true

    echo
    tdz_box_top; tdz_box_header "PORT CONFIGURATION"; tdz_box_divider
    tdz_row "${C_GRAY}Choose one public port and one local backend port.${C_RESET}"
    tdz_box_bot; echo

    while true; do
        prompt_port "Select Public Port" "$public_default" "$backend_default"; PUBLIC_PORT=$REPLY
        if [[ "$PUBLIC_PORT" != "$old_public" ]] && port_is_listening "$PUBLIC_PORT"; then tdz_message error "Port ${PUBLIC_PORT} is already in use."; continue; fi
        break
    done
    prompt_port "Select Backend Port" "$backend_default" "$PUBLIC_PORT"; BACKEND_PORT=$REPLY

    local old_config="$TMP_DIR/old.conf" old_firewall="$TMP_DIR/old-firewall.conf"
    [[ -r "$CONFIG_FILE" ]] && cp -f "$CONFIG_FILE" "$old_config" || : > "$old_config"
    [[ -r "$FIREWALL_STATE" ]] && cp -f "$FIREWALL_STATE" "$old_firewall" || : > "$old_firewall"

    echo
    tdz_box_top; tdz_box_header "FINAL SETUP"; tdz_box_bot; echo
    progress_run 1 4 "Saving port configuration" write_config "$PUBLIC_PORT" "$BACKEND_PORT" || fatal "Could not save ports."
    if [[ "$PUBLIC_PORT" != "$old_public" || ! -r "$FIREWALL_STATE" ]]; then
        progress_run 2 4 "Configuring public firewall" firewall_open "$PUBLIC_PORT" || fatal "Firewall setup failed."
    else
        progress_run 2 4 "Keeping public firewall rule" true
    fi
    progress_run 3 4 "Starting proxy service" systemctl enable --now "$SERVICE_NAME" || fatal "Service failed to start."
    if ! progress_run 4 4 "Validating active proxy" wait_for_service "$PUBLIC_PORT"; then
        firewall_close_file "$FIREWALL_STATE"
        if [[ -s "$old_config" ]]; then cp -f "$old_config" "$CONFIG_FILE"; else rm -f "$CONFIG_FILE"; fi
        if [[ -s "$old_firewall" ]]; then cp -f "$old_firewall" "$FIREWALL_STATE"; else rm -f "$FIREWALL_STATE"; fi
        systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
        fatal "Proxy validation failed; previous settings were restored."
    fi
    if [[ "$PUBLIC_PORT" != "$old_public" && -s "$old_firewall" ]]; then firewall_close_file "$old_firewall"; fi

    echo
    tdz_box_top; tdz_box_header "SETUP COMPLETE"; tdz_box_divider
    tdz_row "${C_GRAY}Public Port:${C_RESET} ${C_WHITE}${PUBLIC_PORT}${C_RESET}"
    tdz_row "${C_GRAY}Backend Port:${C_RESET} ${C_WHITE}127.0.0.1:${BACKEND_PORT}${C_RESET}"
    tdz_row "${C_GRAY}Manager Command:${C_RESET} ${C_GREEN}${C_BOLD}tdzp${C_RESET}"
    tdz_box_divider
    tdz_row "${C_GREEN}TDZ Payload Proxy is active and ready.${C_RESET}"
    tdz_box_bot
    if ! port_is_listening "$BACKEND_PORT"; then echo; tdz_message warning "No local service is currently listening on backend port ${BACKEND_PORT}."; fi
    echo
}

main "$@"
