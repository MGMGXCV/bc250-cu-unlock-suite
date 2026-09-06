#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bc250-common.sh"
need_root; prepare_state; need_exec "$MANAGER"
printf '[bc250-unlock] platform: %s; state=%s\n' "$(bc250_platform_label)" "$STATE_DIR"
"$MANAGER" status
printf '\n[bc250-unlock] boot restore: '
if systemctl is-enabled --quiet "$UPSTREAM_SERVICE" 2>/dev/null; then printf 'ENABLED\n'; else printf 'disabled/not installed\n'; fi
if [ -r "$TOPOLOGY" ]; then
  mapfile -t good < <(approved_wgps 2>/dev/null || true)
  printf '[bc250-unlock] approved WGPs: %s\n' "${good[*]:-none}"
  printf '[bc250-unlock] approved nominal target: %s/40 CUs\n' "$((24 + 2*${#good[@]}))"
fi
t="$(max_amdgpu_temp_c || true)"; [ -n "$t" ] && printf '[bc250-unlock] current maximum amdgpu temperature: %sC\n' "$t" || true
