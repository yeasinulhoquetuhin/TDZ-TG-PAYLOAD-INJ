#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/etc" "$TMP/lib" "$TMP/config"
cp "$ROOT/manager.sh" "$TMP/tdzp"
chmod +x "$TMP/tdzp"
printf 'PUBLIC_PORT=8080\nBACKEND_PORT=22\n' > "$TMP/config/tdzp.conf"

cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  is-active|is-enabled) exit 0 ;;
  show)
    case "$*" in
      *MainPID*) echo 4321 ;;
      *ActiveEnterTimestamp*) echo 'Sun 2026-07-26 12:00:00 +06' ;;
    esac
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF

cat > "$TMP/bin/ss" <<'EOF'
#!/usr/bin/env bash
port=$(awk -F= '$1=="PUBLIC_PORT" {print $2}' "$TEST_CONFIG_FILE")
printf 'LISTEN 0 512 0.0.0.0:%s 0.0.0.0:*\n' "$port"
EOF

cat > "$TMP/bin/sysctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/bin/systemctl" "$TMP/bin/ss" "$TMP/bin/sysctl"

env_args=(
  PATH="$TMP/bin:/usr/bin:/bin"
  TEST_CONFIG_FILE="$TMP/config/tdzp.conf"
  TDZP_CONFIG_DIR="$TMP/config"
  TDZP_CONFIG_FILE="$TMP/config/tdzp.conf"
  TDZP_FIREWALL_STATE="$TMP/config/firewall.conf"
  TDZP_SERVICE_FILE="$TMP/etc/tdz-payload.service"
  TDZP_SYSCTL_FILE="$TMP/etc/99-tdz-payload.conf"
  TDZP_LIB_DIR="$TMP/lib"
  TDZP_MANAGER_BIN="$TMP/tdzp"
  TDZP_MANAGER_ALIAS_UPPER="$TMP/TDZP"
  TDZP_MANAGER_ALIAS_MIXED="$TMP/tdZp"
  TDZP_SYSTEMCTL_BIN="$TMP/bin/systemctl"
  TDZP_SYSCTL_BIN="$TMP/bin/sysctl"
  TDZP_APP_USER="tdzpayload-test-user-not-present"
  TDZP_APP_GROUP="tdzpayload-test-group-not-present"
)

printf '1\n9090\n0\n' | env "${env_args[@]}" "$TMP/tdzp" menu >/dev/null
[[ $(awk -F= '$1=="PUBLIC_PORT" {print $2}' "$TMP/config/tdzp.conf") == 9090 ]]
[[ $(awk -F= '$1=="BACKEND_PORT" {print $2}' "$TMP/config/tdzp.conf") == 22 ]]

printf '2\n2222\n0\n' | env "${env_args[@]}" "$TMP/tdzp" menu >/dev/null
[[ $(awk -F= '$1=="PUBLIC_PORT" {print $2}' "$TMP/config/tdzp.conf") == 9090 ]]
[[ $(awk -F= '$1=="BACKEND_PORT" {print $2}' "$TMP/config/tdzp.conf") == 2222 ]]

env "${env_args[@]}" "$TMP/tdzp" status > "$TMP/status.out"
grep -Fq 'PROXY STATUS' "$TMP/status.out"

: > "$TMP/etc/tdz-payload.service"
: > "$TMP/etc/99-tdz-payload.conf"
printf 'YES\n' | env "${env_args[@]}" "$TMP/tdzp" uninstall >/dev/null
[[ ! -e "$TMP/config" ]]
[[ ! -e "$TMP/lib" ]]
[[ ! -e "$TMP/etc/tdz-payload.service" ]]
[[ ! -e "$TMP/etc/99-tdz-payload.conf" ]]

echo 'Manager sandbox checks passed.'
