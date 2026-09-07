#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bc250-common.sh"
prepare_state
out="${1:-$PWD/bc250-report-$(date +%Y%m%d-%H%M%S).md}"
mkdir -p "$(dirname -- "$out")"
manager_commit="$(git -C "$BC250_ROOT/upstream/bc250-cu-live-manager" rev-parse HEAD 2>/dev/null || echo unknown)"
verify_commit="$(git -C "$BC250_ROOT/upstream/bc250-40cu-unlock" rev-parse HEAD 2>/dev/null || echo unknown)"
mesa_ver="$(pacman -Q mesa 2>/dev/null || echo unknown)"
current="$(current_routed_cus 2>/dev/null || echo unknown)"
temp="$(max_amdgpu_temp_c 2>/dev/null || echo unknown)"
cpu_results="$STATE_DIR/cpu-results.tsv"
cpu_threads="$(nproc 2>/dev/null || echo unknown)"
if systemctl is-enabled --quiet bc250-cpu-rearm.service 2>/dev/null; then cpu_rearm="enabled"; else cpu_rearm="disabled"; fi
{
  echo '# BC-250 CU Unlock Suite report'
  echo
  echo '> Generated locally. Hostname, username and IP addresses are intentionally omitted.'
  echo
  echo '## Environment'
  echo
  printf -- '- Date: `%s`\n' "$(date -Iseconds)"
  printf -- '- Platform: `%s`\n' "$(bc250_platform_label)"
  if [ "$BC250_PLATFORM_DETECTED" = steamos ]; then (. /etc/os-release; printf -- '- SteamOS version: `%s`\n' "${VERSION_ID:-unknown}"); fi
  printf -- '- Kernel: `%s`\n' "$(uname -r)"
  printf -- '- Mesa: `%s`\n' "$mesa_ver"
  printf -- '- Current routed CUs: `%s/40`\n' "$current"
  printf -- '- Current max amdgpu hwmon temp: `%s C`\n' "$temp"
  printf -- '- CPU online threads: `%s`\n' "$cpu_threads"
  printf -- '- CPU automatic re-arm: `%s`\n' "$cpu_rearm"
  printf -- '- live-manager commit: `%s`\n' "$manager_commit"
  printf -- '- 40cu/verifier commit: `%s`\n' "$verify_commit"
  echo
  echo '## Current live dashboard'
  echo
  echo '```text'
  "$MANAGER" status 2>/dev/null || true
  echo '```'
  echo
  echo '## Cached boot topology'
  echo
  echo '```text'
  cat "$TOPOLOGY" 2>/dev/null || echo 'No topology cached.'
  echo '```'
  echo
  echo '## Compute results (latest)'
  echo
  echo '| WGP | Status | Time | Detail |'
  echo '|---|---|---|---|'
  awk -F'\t' '$3!="BASELINE" && $3!="COMBINED"{s[$3]=$4;t[$3]=$1;d[$3]=$5} END{for(w in s) printf "| `%s` | %s | %s | %s |\n",w,s[w],t[w],d[w]}' "$RESULTS" | sort
  echo
  echo '## Visual results (latest)'
  echo
  echo '| WGP | Status | Time | Detail |'
  echo '|---|---|---|---|'
  awk -F'\t' '{s[$3]=$4;t[$3]=$1;d[$3]=$5} END{for(w in s) printf "| `%s` | %s | %s | %s |\n",w,s[w],t[w],d[w]}' "$VISUAL_RESULTS" | sort
  echo
  echo '## Denylist'
  echo
  if [ -s "$DENYLIST" ]; then
    echo '| WGP | Time | Reason |'; echo '|---|---|---|'; awk -F'\t' '{printf "| `%s` | %s | %s |\n",$1,$2,$3}' "$DENYLIST"
  else echo 'None.'; fi
  echo
  echo '## Combined validation'
  echo
  echo '```text'
  awk -F'\t' '$3=="COMBINED"{print}' "$RESULTS" | tail -n 10
  echo '```'
  echo
  echo '## Approved set'
  echo
  mapfile -t good < <(approved_wgps 2>/dev/null || true)
  printf -- '- Approved WGPs: `%s`\n' "${good[*]:-none}"
  printf -- '- Nominal target: `%s/40 CUs`\n' "$((24 + 2*${#good[@]}))"
  echo
  echo '## CPU validation'
  echo
  printf -- '- Current online threads: `%s`\n' "$cpu_threads"
  printf -- '- Automatic re-arm: `%s`\n' "$cpu_rearm"
  if [ -s "$cpu_results" ]; then
    echo
    echo '| Time | Stage | Status | Detail | Log |'
    echo '|---|---|---|---|---|'
    tail -n 20 "$cpu_results" | awk -F'\t' '{printf "| %s | `%s` | %s | %s | `%s` |\n",$1,$2,$3,$4,$5}'
  else
    echo
    echo 'No CPU health-test records.'
  fi
  echo
  echo '## Notes'
  echo
  echo '- `PASS` means the automated compute verifier was clean; it is not a lifetime guarantee.'
  echo '- `PASS_VISUAL` is a human real-desktop check. A visible artifact overrides synthetic PASS results.'
  echo '- Profiles are board-specific. Do not copy another board\x27s WGP mask without testing your own silicon.'
} > "$out"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then chown "$SUDO_USER": "$out" 2>/dev/null || true; fi
printf '%s\n' "$out"
