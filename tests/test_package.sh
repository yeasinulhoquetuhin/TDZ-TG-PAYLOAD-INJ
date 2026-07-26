#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

bash -n "$ROOT/install.sh"
bash -n "$ROOT/manager.sh"
python3 -m py_compile "$ROOT/tdz_payload_proxy.py"
python3 -m unittest -v "$ROOT/tests/test_payload_proxy.py"
"$ROOT/tests/test_manager.sh"

grep -Fq 'TDZ PAYLOAD PROXY' "$ROOT/install.sh"
grep -Fq 'Powered By: t.me/TuhinBroh' "$ROOT/manager.sh"
! grep -Fq 'Payload Injection  •  Speed Boost' "$ROOT/install.sh"
! grep -Fq 'Payload Injection  •  Speed Boost' "$ROOT/manager.sh"
grep -Fq 'Edit Public Port' "$ROOT/manager.sh"
grep -Fq 'Edit Backend Port' "$ROOT/manager.sh"
grep -Fq 'View Proxy Status' "$ROOT/manager.sh"
grep -Fq 'Uninstall TDZ Payload Proxy' "$ROOT/manager.sh"

if grep -Eqi 'FORIDUL|Telegram Bypass|Create New Proxy Instance|List All Instances|Change Payload Mode' "$ROOT"/*.sh "$ROOT"/*.py; then
    echo 'Unexpected old branding or removed feature text found.' >&2
    exit 1
fi

echo 'All package checks passed.'
