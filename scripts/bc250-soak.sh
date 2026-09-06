#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bc250-common.sh"

minutes="${1:-20}"
[[ "$minutes" =~ ^[0-9]+$ ]] && [ "$minutes" -ge 1 ] || lab_die "usage: sudo ./bc250-unlock soak MINUTES"
need_root; prepare_state; need_exec "$MANAGER"; need_exec "$VERIFY"
command -v timeout >/dev/null 2>&1 || lab_die "missing command: timeout"
command -v setsid >/dev/null 2>&1 || lab_die "missing command: setsid"
[ ! -e "$STATE_DIR/gpu-pending" ] || lab_die "pending marker exists; run recover first"
mapfile -t good < <(approved_wgps)
[ "${#good[@]}" -gt 0 ] || lab_die "no approved WGPs; finish compute + visual validation first"
expected=$((24 + 2*${#good[@]}))
start="$(date +%s)"; end=$((start + minutes*60))
logdir="$STATE_DIR/logs"; mkdir -p "$logdir"
log="$logdir/soak-${expected}cu-$(date +%Y%m%d-%H%M%S).log"

cleanup(){ local rc=$?; trap - EXIT INT TERM HUP; if [ "$rc" -ne 0 ]; then lab_warn "soak aborted; restoring stock 24-CU routing"; manager stock-dispatch >/dev/null 2>&1 || true; fi; exit "$rc"; }
trap cleanup EXIT INT TERM HUP

run_verify_guarded(){
  local epoch="$1" pid rc temp thermal=0
  setsid timeout --signal=TERM --kill-after=10s 300s \
    "$VERIFY" --elements 16777216 --passes 2 --iters 64 >>"$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    temp="$(max_amdgpu_temp_c || true)"
    [ -n "$temp" ] && printf '[temp] %s C\n' "$temp" >>"$log"
    if [ -n "$temp" ] && [ "$temp" -ge "$MAX_TEMP_C" ]; then
      thermal=1
      lab_warn "thermal cutoff reached (${temp}C); stopping verifier"
      kill -TERM -- "-$pid" 2>/dev/null || true
      sleep 2
      kill -KILL -- "-$pid" 2>/dev/null || true
      break
    fi
    sleep 1
  done
  if wait "$pid"; then rc=0; else rc=$?; fi
  [ "$thermal" -eq 0 ] || return 200
  return "$rc"
}

lab_say "applying approved set: ${good[*]} => ${expected}/40 CUs"
manager stock-dispatch >>"$log" 2>&1
manager enable-wgp "${good[@]}" >>"$log" 2>&1
live="$(current_routed_cus || true)"; [ "$live" = "$expected" ] || lab_die "expected $expected routed CUs, got ${live:-unknown}"
lab_say "soak test: ${minutes} min, continuous thermal cutoff ${MAX_TEMP_C}C; log=$log"
cycle=0
while [ "$(date +%s)" -lt "$end" ]; do
  cycle=$((cycle+1)); now="$(date +%s)"; remain=$(( (end-now+59)/60 ))
  temp="$(max_amdgpu_temp_c || true)"; [ -n "$temp" ] && lab_say "cycle $cycle; ~${remain} min left; temp=${temp}C" || lab_say "cycle $cycle; ~${remain} min left"
  if [ -n "$temp" ] && [ "$temp" -ge "$MAX_TEMP_C" ]; then lab_die "thermal cutoff reached (${temp}C)"; fi
  epoch="$(date +%s)"
  if run_verify_guarded "$epoch"; then rc=0; else rc=$?; fi
  [ "$rc" -ne 200 ] || lab_die "thermal cutoff reached during verifier"
  [ "$rc" -eq 0 ] || lab_die "compute verifier failed during soak (cycle $cycle, rc=$rc)"
  faults="$(kernel_faults_since "$epoch")"
  if [ -n "$faults" ]; then printf '\n--- kernel faults cycle %s ---\n%s\n' "$cycle" "$faults" >>"$log"; lab_die "kernel GPU/hardware fault detected during soak"; fi
done
trap - EXIT INT TERM HUP
lab_say "SOAK PASS: ${expected}/40 CUs survived ${minutes} min; approved set left active live"
lab_say "log: $log"
