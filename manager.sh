#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${TDZP_CONFIG_DIR:-/etc/tdz-payload}"
CONFIG_FILE="${TDZP_CONFIG_FILE:-$CONFIG_DIR/tdzp.conf}"
FIREWALL_STATE="${TDZP_FIREWALL_STATE:-$CONFIG_DIR/firewall.conf}"
SERVICE_NAME="${TDZP_SERVICE_NAME:-tdz-payload.service}"
SERVICE_FILE="${TDZP_SERVICE_FILE:-/etc/systemd/system/$SERVICE_NAME}"
SYSCTL_FILE="${TDZP_SYSCTL_FILE:-/etc/sysctl.d/99-tdz-payload.conf}"
LIB_DIR="${TDZP_LIB_DIR:-/usr/local/lib/tdz-payload}"
MANAGER_BIN="${TDZP_MANAGER_BIN:-/usr/local/bin/tdzp}"
MANAGER_ALIAS_UPPER="${TDZP_MANAGER_ALIAS_UPPER:-/usr/local/bin/TDZP}"
MANAGER_ALIAS_MIXED="${TDZP_MANAGER_ALIAS_MIXED:-/usr/local/bin/tdZp}"
SYSTEMCTL_BIN="${TDZP_SYSTEMCTL_BIN:-systemctl}"
SYSCTL_BIN="${TDZP_SYSCTL_BIN:-sysctl}"
APP_USER="${TDZP_APP_USER:-tdzpayload}"
APP_GROUP="${TDZP_APP_GROUP:-tdzpayload}"

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[38;5;196m'; C_GREEN=$'\033[38;5;46m'; C_YELLOW=$'\033[38;5;226m'
    C_NAVY=$'\033[38;5;39m'; C_BLUE=$'\033[38;2;0;212;255m'; C_CYAN=$C_BLUE
    C_WHITE=$'\033[38;5;255m'; C_GRAY=$'\033[38;5;245m'; C_CHOICE=$C_CYAN
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
    C_NAVY=''; C_BLUE=''; C_CYAN=''; C_WHITE=''; C_GRAY=''; C_CHOICE=''
fi
C_TITLE=$C_NAVY; C_PROMPT=$C_BLUE; C_DANGER=$C_RED

TDZ_BOX_WIDTH=58
if [[ -t 1 ]]; then
    cols=${COLUMNS:-}
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=$(tput cols 2>/dev/null || printf '80')
    (( cols - 4 < TDZ_BOX_WIDTH )) && TDZ_BOX_WIDTH=$((cols - 4))
    (( TDZ_BOX_WIDTH < 38 )) && TDZ_BOX_WIDTH=38
fi

strip_ansi() { printf '%b' "$1" | sed -E $'s/\x1B\[[0-9;]*[mK]//g'; }
text_width() { local text; text=$(strip_ansi "$1"); printf '%s' "${#text}"; }
fit_text() {
    local text=$1 max=$2 plain
    plain=$(strip_ansi "$text")
    if (( ${#plain} <= max )); then printf '%s' "$text"; else printf '%s...' "${plain:0:max-3}"; fi
}
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
tdz_row() {
    local text=$1 color=${2:-$C_TITLE} width pad
    text=$(fit_text "$text" $((TDZ_BOX_WIDTH - 2)))
    width=$(text_width "$text"); pad=$((TDZ_BOX_WIDTH - width - 1)); (( pad < 1 )) && pad=1
    printf '  %b│%b %s%*s%b│%b\n' "$color" "$C_RESET" "$text" "$pad" '' "$color" "$C_RESET"
}
tdz_box_header() {
    local text=$1 color=${2:-$C_TITLE}
    tdz_row "${C_BOLD}${C_GREEN}▶ $(fit_text "$text" $((TDZ_BOX_WIDTH - 5)))${C_RESET}" "$color"
}
tdz_menu1() { tdz_row "${C_CHOICE}$1${C_RESET} ${C_WHITE}$2${C_RESET}" "${3:-$C_TITLE}"; }
tdz_detail() { printf '  %b• %-18s%b %b%s%b\n' "$C_GRAY" "$1:" "$C_RESET" "${3:-$C_WHITE}" "$2" "$C_RESET"; }
tdz_message() {
    local kind=${1^^} msg=$2 color label
    case "$kind" in
        OK|SUCCESS) color=$C_GREEN; label=OK ;;
        INFO) color=$C_BLUE; label=INFO ;;
        WARNING|WARN) color=$C_YELLOW; label=WARNING ;;
        *) color=$C_RED; label=ERROR ;;
    esac
    printf '  %b[%s]%b %s\n' "$color" "$label" "$C_RESET" "$msg"
}
pause_screen() { [[ -t 0 ]] || return 0; echo; read -r -p "$(printf '%b' "${C_GRAY}  Press Enter to continue...${C_RESET}")" _; }

show_banner() {
    [[ -t 1 ]] && clear || true
    echo
    tdz_banner_top
    tdz_center_row "TDZ PAYLOAD PROXY" "${C_BOLD}${C_CYAN}TDZ PAYLOAD PROXY${C_RESET}"
    tdz_center_row "Powered By: t.me/TuhinBroh" "${C_GRAY}Powered By: t.me/TuhinBroh${C_RESET}"
    tdz_banner_bot
}

require_root() {
    if (( EUID != 0 )); then
        tdz_message error "Run tdzp as root."
        exit 1
    fi
}
svc() { "$SYSTEMCTL_BIN" "$@"; }
validate_port() { [[ ${1:-} =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
config_value() { awk -F= -v key="$1" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$CONFIG_FILE" 2>/dev/null; }
load_config() {
    [[ -r "$CONFIG_FILE" ]] || { tdz_message error "TDZ Payload Proxy is not configured."; exit 1; }
    PUBLIC_PORT=$(config_value PUBLIC_PORT)
    BACKEND_PORT=$(config_value BACKEND_PORT)
    validate_port "$PUBLIC_PORT" && validate_port "$BACKEND_PORT" || { tdz_message error "Invalid saved port configuration."; exit 1; }
}
write_config() {
    local public=$1 backend=$2 tmp
    install -d -m 0750 "$CONFIG_DIR"
    tmp=$(mktemp "$CONFIG_DIR/.tdzp.XXXXXX")
    printf 'PUBLIC_PORT=%s\nBACKEND_PORT=%s\n' "$public" "$backend" > "$tmp" || return 1
    chmod 0640 "$tmp" || return 1
    chown root:"$APP_GROUP" "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$CONFIG_FILE" || return 1
}
port_is_listening() {
    local port=$1
    command -v ss >/dev/null 2>&1 || return 1
    ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[:.]|\\])${port}$"
}
backend_is_listening() { port_is_listening "$BACKEND_PORT"; }
service_active() { svc is-active --quiet "$SERVICE_NAME" 2>/dev/null; }
service_enabled() { svc is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; }

read_state_value() {
    local file=$1 key=$2
    awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$file" 2>/dev/null
}
write_firewall_state() {
    local method=$1 port=$2 added=$3 tmp
    install -d -m 0750 "$CONFIG_DIR"
    tmp=$(mktemp "$CONFIG_DIR/.firewall.XXXXXX")
    printf 'METHOD=%s\nPORT=%s\nADDED=%s\n' "$method" "$port" "$added" > "$tmp"
    chmod 0600 "$tmp"; mv -f "$tmp" "$FIREWALL_STATE"
}
firewall_open() {
    local port=$1 method=none added=0
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
        method=ufw
        if ! ufw status 2>/dev/null | grep -Eq "^${port}/tcp[[:space:]]+ALLOW"; then
            ufw allow "$port/tcp" comment 'TDZ Payload Proxy' >/dev/null
            added=1
        fi
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        method=firewalld
        if ! firewall-cmd --permanent --query-port="${port}/tcp" >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null
            firewall-cmd --reload >/dev/null
            added=1
        fi
    elif command -v iptables >/dev/null 2>&1; then
        method=iptables
        if ! iptables -C INPUT -p tcp --dport "$port" -m comment --comment TDZ_PAYLOAD_PROXY -j ACCEPT >/dev/null 2>&1; then
            iptables -I INPUT -p tcp --dport "$port" -m comment --comment TDZ_PAYLOAD_PROXY -j ACCEPT
            added=1
        fi
    fi
    write_firewall_state "$method" "$port" "$added"
}
firewall_close_file() {
    local state_file=$1 method port added
    [[ -r "$state_file" ]] || return 0
    method=$(read_state_value "$state_file" METHOD)
    port=$(read_state_value "$state_file" PORT)
    added=$(read_state_value "$state_file" ADDED)
    [[ "$added" == 1 ]] || return 0
    case "$method" in
        ufw) ufw --force delete allow "$port/tcp" >/dev/null 2>&1 || true ;;
        firewalld)
            firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            ;;
        iptables)
            iptables -D INPUT -p tcp --dport "$port" -m comment --comment TDZ_PAYLOAD_PROXY -j ACCEPT >/dev/null 2>&1 || true
            ;;
    esac
}

prompt_port() {
    local label=$1 current=$2 other=$3 value
    while true; do
        read -r -p "$(printf '%b' "${C_PROMPT}  ${label} [${current}]: ${C_RESET}")" value
        value=${value:-$current}
        if ! validate_port "$value"; then
            tdz_message error "Enter a port between 1 and 65535."
        elif [[ "$value" == "$other" ]]; then
            tdz_message error "Public and backend ports must be different."
        else
            REPLY=$value
            return 0
        fi
    done
}

wait_for_service() {
    local expected_port=$1 i
    for ((i=0; i<20; i++)); do
        if service_active && port_is_listening "$expected_port"; then return 0; fi
        sleep 0.15
    done
    return 1
}

edit_public_port() {
    show_banner
    echo
    tdz_box_top; tdz_box_header "EDIT PUBLIC PORT"; tdz_box_bot; echo
    load_config
    prompt_port "New public port" "$PUBLIC_PORT" "$BACKEND_PORT"
    local new_port=$REPLY old_port=$PUBLIC_PORT old_state old_conf
    [[ "$new_port" == "$old_port" ]] && { tdz_message info "Public port is unchanged."; pause_screen; return; }
    if port_is_listening "$new_port"; then
        tdz_message error "Port ${new_port} is already in use."
        pause_screen; return
    fi
    old_state=$(mktemp); old_conf=$(mktemp)
    [[ -r "$FIREWALL_STATE" ]] && cp -f "$FIREWALL_STATE" "$old_state" || : > "$old_state"
    cp -f "$CONFIG_FILE" "$old_conf"

    if ! firewall_open "$new_port" || ! write_config "$new_port" "$BACKEND_PORT" || ! svc restart "$SERVICE_NAME" >/dev/null 2>&1 || ! wait_for_service "$new_port"; then
        cp -f "$old_conf" "$CONFIG_FILE"
        firewall_close_file "$FIREWALL_STATE"
        [[ -s "$old_state" ]] && cp -f "$old_state" "$FIREWALL_STATE" || rm -f "$FIREWALL_STATE"
        svc restart "$SERVICE_NAME" >/dev/null 2>&1 || true
        rm -f "$old_state" "$old_conf"
        tdz_message error "Port change failed. Previous settings were restored."
        pause_screen; return
    fi
    firewall_close_file "$old_state"
    rm -f "$old_state" "$old_conf"
    tdz_message ok "Public port changed: ${old_port} → ${new_port}"
    pause_screen
}

edit_backend_port() {
    show_banner
    echo
    tdz_box_top; tdz_box_header "EDIT BACKEND PORT"; tdz_box_bot; echo
    load_config
    prompt_port "New backend port" "$BACKEND_PORT" "$PUBLIC_PORT"
    local new_port=$REPLY old_port=$BACKEND_PORT backup
    [[ "$new_port" == "$old_port" ]] && { tdz_message info "Backend port is unchanged."; pause_screen; return; }
    backup=$(mktemp); cp -f "$CONFIG_FILE" "$backup"
    if ! write_config "$PUBLIC_PORT" "$new_port" || ! svc restart "$SERVICE_NAME" >/dev/null 2>&1 || ! wait_for_service "$PUBLIC_PORT"; then
        cp -f "$backup" "$CONFIG_FILE"
        svc restart "$SERVICE_NAME" >/dev/null 2>&1 || true
        rm -f "$backup"
        tdz_message error "Backend port change failed. Previous settings were restored."
        pause_screen; return
    fi
    rm -f "$backup"
    BACKEND_PORT=$new_port
    tdz_message ok "Backend port changed: ${old_port} → ${new_port}"
    if ! backend_is_listening; then
        tdz_message warning "Nothing is listening on 127.0.0.1:${new_port} right now."
    fi
    pause_screen
}

show_status() {
    show_banner
    echo
    tdz_box_top; tdz_box_header "PROXY STATUS"; tdz_box_divider
    load_config
    local active enabled listening backend status_color pid uptime_text
    if service_active; then active=ACTIVE; status_color=$C_GREEN; else active=INACTIVE; status_color=$C_RED; fi
    if service_enabled; then enabled=Enabled; else enabled=Disabled; fi
    if port_is_listening "$PUBLIC_PORT"; then listening=Listening; else listening='Not listening'; fi
    if backend_is_listening; then backend=Ready; else backend='No local listener'; fi
    pid=$(svc show "$SERVICE_NAME" -p MainPID --value 2>/dev/null || printf '0')
    uptime_text=$(svc show "$SERVICE_NAME" -p ActiveEnterTimestamp --value 2>/dev/null || true)
    tdz_row "${C_GRAY}Service:${C_RESET} ${status_color}${C_BOLD}${active}${C_RESET}"
    tdz_row "${C_GRAY}Auto Start:${C_RESET} ${C_WHITE}${enabled}${C_RESET}"
    tdz_row "${C_GRAY}Public Port:${C_RESET} ${C_WHITE}${PUBLIC_PORT}${C_RESET}  ${C_GRAY}(${listening})${C_RESET}"
    tdz_row "${C_GRAY}Backend:${C_RESET} ${C_WHITE}127.0.0.1:${BACKEND_PORT}${C_RESET}  ${C_GRAY}(${backend})${C_RESET}"
    [[ "$pid" != 0 && -n "$pid" ]] && tdz_row "${C_GRAY}Process ID:${C_RESET} ${C_WHITE}${pid}${C_RESET}"
    [[ -n "$uptime_text" ]] && tdz_row "${C_GRAY}Started:${C_RESET} ${C_WHITE}${uptime_text}${C_RESET}"
    tdz_box_bot
    echo
    tdz_detail "Payload Response" "HTTP/1.1 101 Switching Protocols"
    tdz_detail "Command" "tdzp"
    pause_screen
}

progress_step() {
    local current=$1 total=$2 label=$3; shift 3
    printf '  %b[%s/%s]%b %-34s' "$C_CYAN" "$current" "$total" "$C_RESET" "$label"
    if "$@" >/dev/null 2>&1; then printf '%b✓%b\n' "$C_GREEN" "$C_RESET"; return 0; fi
    printf '%b✗%b\n' "$C_RED" "$C_RESET"; return 1
}

remove_managed_files() {
    rm -f "$MANAGER_BIN" "$MANAGER_ALIAS_UPPER" "$MANAGER_ALIAS_MIXED"
    rm -rf "$LIB_DIR" "$CONFIG_DIR"
    rm -f "$SERVICE_FILE" "$SYSCTL_FILE"
}
remove_app_user() {
    if id "$APP_USER" >/dev/null 2>&1; then userdel "$APP_USER" >/dev/null 2>&1 || true; fi
    if getent group "$APP_GROUP" >/dev/null 2>&1; then groupdel "$APP_GROUP" >/dev/null 2>&1 || true; fi
}

uninstall_proxy() {
    show_banner
    echo
    tdz_box_top "$C_DANGER"; tdz_box_header "UNINSTALL TDZ PAYLOAD PROXY" "$C_DANGER"
    tdz_box_divider "$C_DANGER"
    tdz_row "${C_YELLOW}All TDZ Payload Proxy files and settings will be removed.${C_RESET}" "$C_DANGER"
    tdz_box_bot "$C_DANGER"
    echo
    local answer state_copy
    read -r -p "$(printf '%b' "${C_RED}  Type YES to uninstall: ${C_RESET}")" answer
    [[ "$answer" == YES ]] || { tdz_message info "Uninstall cancelled."; pause_screen; return; }
    state_copy=$(mktemp)
    [[ -r "$FIREWALL_STATE" ]] && cp -f "$FIREWALL_STATE" "$state_copy" || : > "$state_copy"
    echo
    progress_step 1 5 "Stopping proxy service" svc disable --now "$SERVICE_NAME" || true
    progress_step 2 5 "Removing managed firewall rule" firewall_close_file "$state_copy" || true
    progress_step 3 5 "Removing service and commands" remove_managed_files || true
    progress_step 4 5 "Restoring network settings" "$SYSCTL_BIN" --system || true
    progress_step 5 5 "Reloading system services" svc daemon-reload || true
    remove_app_user
    rm -f "$state_copy"
    echo
    tdz_message ok "TDZ Payload Proxy was completely uninstalled."
    exit 0
}

main_menu() {
    while true; do
        load_config
        show_banner
        local svc_text svc_color
        if service_active; then svc_text=ACTIVE; svc_color=$C_GREEN; else svc_text=INACTIVE; svc_color=$C_RED; fi
        echo
        tdz_box_top
        tdz_box_header "PROXY MANAGEMENT"
        tdz_box_divider
        tdz_row "${C_GRAY}Status:${C_RESET} ${svc_color}${C_BOLD}${svc_text}${C_RESET}  ${C_GRAY}Public:${C_RESET} ${C_WHITE}${PUBLIC_PORT}${C_RESET}  ${C_GRAY}Backend:${C_RESET} ${C_WHITE}${BACKEND_PORT}${C_RESET}"
        tdz_box_divider
        tdz_menu1 "[ 1]" "Edit Public Port"
        tdz_menu1 "[ 2]" "Edit Backend Port"
        tdz_menu1 "[ 3]" "View Proxy Status"
        tdz_menu1 "[ 0]" "Exit"
        tdz_box_divider "$C_DANGER"
        tdz_menu1 "[99]" "Uninstall TDZ Payload Proxy" "$C_DANGER"
        tdz_box_bot
        echo
        local choice
        read -r -p "$(printf '%b' "${C_PROMPT}  Select option: ${C_RESET}")" choice
        case "$choice" in
            1) edit_public_port ;;
            2) edit_backend_port ;;
            3) show_status ;;
            0|q|Q) exit 0 ;;
            99) uninstall_proxy ;;
            *) tdz_message error "Invalid option."; sleep 1 ;;
        esac
    done
}

require_root
case "${1:-menu}" in
    menu) main_menu ;;
    status) show_status ;;
    uninstall) uninstall_proxy ;;
    *) tdz_message error "Usage: tdzp [status|uninstall]"; exit 2 ;;
esac
