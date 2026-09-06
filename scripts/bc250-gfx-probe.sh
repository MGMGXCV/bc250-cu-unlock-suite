#!/usr/bin/env bash
# BC-250 offscreen graphics WGP probe.
# Experimental companion to bc250-gpu-probe.sh: compares deterministic GLES3
# framebuffer readbacks against a self-checked stock 24-CU reference.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bc250-platform.sh
source "$SCRIPT_DIR/bc250-platform.sh"
if [ -n "${BC250_STATE_DIR:-}" ]; then
  STATE_DIR="$BC250_STATE_DIR"
elif [ "$(bc250_detect_platform)" = steamos ]; then
  STATE_DIR="$(bc250_steamos_state_dir)"
else
  STATE_DIR="/var/lib/bc250-probe"
fi
MANAGER="${BC250_MANAGER:-$SCRIPT_DIR/../upstream/bc250-cu-live-manager/bc250-cu-live-manager.sh}"
GFX_VERIFY="${BC250_GFX_VERIFY:-$SCRIPT_DIR/bc250-graphics-verify.py}"
MAIN_RESULTS="$STATE_DIR/gpu-results.tsv"
RESULTS="$STATE_DIR/gpu-graphics-results.tsv"
REFERENCE="$STATE_DIR/gfx-reference-v2.json"
PENDING="$STATE_DIR/gfx-pending"
LOG_DIR="$STATE_DIR/logs"
LOCK_FILE="$STATE_DIR/gfx.lock"
SERVICE="bc250-cu-live-manager.service"
MAX_TEMP_C="${BC250_MAX_TEMP_C:-95}"
GFX_TIMEOUT="${BC250_GFX_TIMEOUT:-420}"

EXTRA_WGPS=()
FACTORY_WGPS=()
ACTIVE_TEST=0
CURRENT_WGP=""
THERMAL_ABORT=0

say(){ printf '[bc250-gfx-probe] %s\n' "$*"; }
warn(){ printf '[bc250-gfx-probe] WARNING: %s\n' "$*" >&2; }
die(){ printf '[bc250-gfx-probe] ERROR: %s\n' "$*" >&2; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "run as root (sudo)"; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
boot_id(){ cat /proc/sys/kernel/random/boot_id; }

usage(){ cat <<'EOF'
Usage:
  sudo ./bc250-gfx-probe.sh preflight
  sudo ./bc250-gfx-probe.sh baseline
  sudo ./bc250-gfx-probe.sh test SE.SH.WGP
  sudo ./bc250-gfx-probe.sh scan
  sudo ./bc250-gfx-probe.sh recover
  ./bc250-gfx-probe.sh summary
  sudo ./bc250-gfx-probe.sh stock

Calibration recommended on a board with known visual-bad WGPs:
  sudo ./bc250-gfx-probe.sh baseline
  sudo ./bc250-gfx-probe.sh test 0.1.3
  sudo ./bc250-gfx-probe.sh test 0.1.4

The detector renders deterministic integer + quantized-FP fragment workloads offscreen through
Mesa EGL/GLES3 and compares per-frame/per-64px-tile SHA-256 hashes against the stock
24-CU reference. It does not inspect the physical HDMI/DP signal itself.

Environment knobs:
  BC250_GFX_WIDTH=512 BC250_GFX_HEIGHT=512
  BC250_GFX_PASSES=6 BC250_GFX_ROUNDS=64 BC250_GFX_REPEATS=16
  BC250_GFX_MIN_SECONDS=4
  BC250_GFX_TIMEOUT=420 BC250_MAX_TEMP_C=95
EOF
}

prepare_state(){ mkdir -p "$STATE_DIR" "$LOG_DIR"; touch "$RESULTS"; chmod 0700 "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true; }
lock_probe(){ need_cmd flock; exec 9>"$LOCK_FILE"; flock -n 9 || die "another graphics probe is already running"; }
check_bc250(){ need_cmd lspci; lspci -Dnn | grep -Eqi '\[1002:13fe\]' || die "AMD BC-250 PCI ID 1002:13fe not detected"; }
check_deps(){ [ -x "$MANAGER" ] || die "live-manager missing: $MANAGER"; [ -x "$GFX_VERIFY" ] || die "graphics verifier missing/executable: $GFX_VERIFY"; need_cmd python3; need_cmd timeout; need_cmd setsid; }

check_no_persistence(){
  if systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
    die "$SERVICE is enabled; disable boot restore while probing"
  fi
  if grep -RqsE '(bc250_cc_write_mode|disable_cu)=' /etc/modprobe.d 2>/dev/null || grep -Eq 'amdgpu\.(disable_cu|bc250_cc_write_mode)=' /proc/cmdline 2>/dev/null; then
    die "old persistent CU override detected; boot clean before probing"
  fi
}

manager(){ "$MANAGER" --yes "$@"; }
restore_stock(){ manager stock-dispatch; }

# Parse D+/D! as driver WGPs and S+/-- as boot-map-disabled candidates.
discover_wgp_topology(){
  local out line row cell se sh w c0 c1 c2 c3 c4
  local -a parsed=()
  out="$("$MANAGER" status)" || die "cannot read live-manager topology"
  mapfile -t parsed < <(printf '%s\n' "$out" | awk -F'|' '
    $2 ~ /SE[01]\.SH[01]/ { row=$2; gsub(/[[:space:]]/,"",row); printf "%s",row;
      for(i=3;i<=7;i++){cell=$i;gsub(/[[:space:]]/,"",cell);printf "\t%s",cell} printf "\n" }')
  [ "${#parsed[@]}" -eq 4 ] || die "could not parse four SE/SH rows"
  FACTORY_WGPS=(); EXTRA_WGPS=()
  for line in "${parsed[@]}"; do
    IFS=$'\t' read -r row c0 c1 c2 c3 c4 <<<"$line"
    [[ "$row" =~ ^SE([01])\.SH([01])$ ]] || die "bad row: $row"
    se="${BASH_REMATCH[1]}"; sh="${BASH_REMATCH[2]}"
    for w in 0 1 2 3 4; do
      case "$w" in 0) cell="$c0";;1) cell="$c1";;2) cell="$c2";;3) cell="$c3";;4) cell="$c4";;esac
      case "$cell" in D+|D!) FACTORY_WGPS+=("$se.$sh.$w");; S+|--) EXTRA_WGPS+=("$se.$sh.$w");; *) die "unexpected cell $cell";; esac
    done
  done
  [ "${#FACTORY_WGPS[@]}" -eq 12 ] || die "expected 12 factory WGPs, got ${#FACTORY_WGPS[@]}"
  [ "${#EXTRA_WGPS[@]}" -eq 8 ] || die "expected 8 candidates, got ${#EXTRA_WGPS[@]}"
}

is_extra(){ local q="$1" x; for x in "${EXTRA_WGPS[@]}"; do [ "$x" = "$q" ] && return 0; done; return 1; }

max_amdgpu_temp_c(){
  local hw f raw max=""
  for hw in /sys/class/drm/card*/device/hwmon/hwmon*; do
    [ -r "$hw/name" ] || continue; grep -q '^amdgpu$' "$hw/name" 2>/dev/null || continue
    for f in "$hw"/temp*_input; do [ -r "$f" ] || continue; raw="$(cat "$f" 2>/dev/null || true)"; [[ "$raw" =~ ^[0-9]+$ ]] || continue; raw=$((raw/1000)); [ -z "$max" ] || [ "$raw" -le "$max" ] || max="$raw"; [ -n "$max" ] || max="$raw"; done
  done
  [ -n "$max" ] && printf '%s\n' "$max"
}

append_result(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$(boot_id)" "$1" "$2" "$3" "$4" >>"$RESULTS"; sync "$RESULTS" 2>/dev/null || true; }
write_pending(){ cat >"$PENDING" <<EOF
wgp=$1
phase=$2
boot_id=$(boot_id)
time=$(date -Iseconds)
EOF
sync "$PENDING" 2>/dev/null || true; }
clear_pending(){ rm -f "$PENDING"; sync "$STATE_DIR" 2>/dev/null || true; }

run_guarded(){
  local logfile="$1" mode="$2" pid rc t
  THERMAL_ABORT=0
  setsid timeout --signal=TERM --kill-after=10s "${GFX_TIMEOUT}s" \
    "$GFX_VERIFY" "$mode" --reference "$REFERENCE" >>"$logfile" 2>&1 & pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    t="$(max_amdgpu_temp_c || true)"; [ -n "$t" ] && printf '[temp] %s C\n' "$t" >>"$logfile"
    if [ -n "$t" ] && [ "$t" -ge "$MAX_TEMP_C" ]; then
      THERMAL_ABORT=1; warn "GPU reached ${t}C (limit ${MAX_TEMP_C}C); stopping graphics verifier"
      kill -TERM -- "-$pid" 2>/dev/null || true; sleep 2; kill -KILL -- "-$pid" 2>/dev/null || true; break
    fi
    sleep 1
  done
  if wait "$pid"; then rc=0; else rc=$?; fi
  return "$rc"
}

cleanup(){ local rc=$?; trap - EXIT INT TERM HUP; if [ "$ACTIVE_TEST" -eq 1 ]; then warn "abnormal exit during ${CURRENT_WGP:-unknown}; attempting stock restore"; restore_stock >/dev/null 2>&1 || true; fi; exit "$rc"; }
trap cleanup EXIT INT TERM HUP

preflight(){
  need_root; prepare_state; lock_probe; check_bc250; check_deps; check_no_persistence; discover_wgp_topology
  say "factory WGPs: ${FACTORY_WGPS[*]}"; say "candidates: ${EXTRA_WGPS[*]}"
  "$GFX_VERIFY" info --reference "$REFERENCE"
  if [ -f "$REFERENCE" ]; then say "graphics stock reference exists: $REFERENCE"; else say "no graphics reference yet; run baseline"; fi
}

baseline(){
  need_root; prepare_state; lock_probe; check_bc250; check_deps; check_no_persistence; discover_wgp_topology
  [ ! -e "$PENDING" ] || die "pending graphics marker exists; run recover"
  local log="$LOG_DIR/gfx-baseline-$(date +%Y%m%d-%H%M%S).log" rc
  say "restoring stock 24-CU routing and generating a self-checked graphics reference"
  restore_stock >>"$log" 2>&1
  if run_guarded "$log" baseline; then rc=0; else rc=$?; fi
  if [ "$THERMAL_ABORT" -eq 1 ]; then append_result BASELINE FAIL_THERMAL "thermal cutoff" "$log"; die "graphics baseline thermal cutoff"; fi
  if [ "$rc" -ne 0 ]; then append_result BASELINE FAIL "graphics baseline rc=$rc" "$log"; tail -n 30 "$log" >&2; die "graphics baseline failed"; fi
  append_result BASELINE PASS "stock reference deterministic" "$log"; say "graphics baseline PASS; reference=$REFERENCE"
}

test_one(){
  local wgp="$1"; discover_wgp_topology; is_extra "$wgp" || die "$wgp is not a candidate on this board: ${EXTRA_WGPS[*]}"
  [ -f "$REFERENCE" ] || die "no stock graphics reference; run baseline first"; [ ! -e "$PENDING" ] || die "pending marker exists; run recover"
  local log="$LOG_DIR/gfx-${wgp//./_}-$(date +%Y%m%d-%H%M%S).log" rc status detail
  restore_stock >>"$log" 2>&1; write_pending "$wgp" before-enable; ACTIVE_TEST=1; CURRENT_WGP="$wgp"
  say "enabling $wgp (+2 CUs) and comparing graphics output with stock reference"
  manager enable-wgp "$wgp" >>"$log" 2>&1; write_pending "$wgp" running-offscreen-graphics
  if run_guarded "$log" verify; then rc=0; else rc=$?; fi
  if ! restore_stock >>"$log" 2>&1; then append_result "$wgp" FAIL_RESTORE "stock restore failed" "$log"; ACTIVE_TEST=0; die "restore failed; reboot"; fi
  ACTIVE_TEST=0; CURRENT_WGP=""
  if [ "$THERMAL_ABORT" -eq 1 ]; then status=FAIL_THERMAL; detail="thermal cutoff"
  elif [ "$rc" -eq 0 ]; then status=PASS; detail="offscreen framebuffer matches stock exactly"
  elif [ "$rc" -eq 2 ]; then status=FAIL_GRAPHICS_AUTO; detail="frame/tile hash mismatch"
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then status=FAIL_TIMEOUT; detail="graphics verifier timeout rc=$rc"
  else status=FAIL_TOOL; detail="graphics verifier rc=$rc"; fi
  append_result "$wgp" "$status" "$detail" "$log"; clear_pending; say "$wgp => $status ($detail)"
  if [ "$status" = FAIL_GRAPHICS_AUTO ]; then say "mismatch details:"; grep '\[bc250-gfx\] MISMATCH:' "$log" | tail -n 12 || true; fi
  [ "$status" = PASS ]
}

scan(){
  need_root; prepare_state; lock_probe; check_bc250; check_deps; check_no_persistence; discover_wgp_topology
  [ -f "$REFERENCE" ] || die "run graphics baseline first"
  local w mainst
  for w in "${EXTRA_WGPS[@]}"; do
    mainst=""; [ -r "$MAIN_RESULTS" ] && mainst="$(awk -F'\t' -v w="$w" '$3==w{s=$4} END{print s}' "$MAIN_RESULTS")"
    if [ -n "$mainst" ] && [ "$mainst" != PASS ]; then say "skipping $w because main probe latest=$mainst (explicit 'test $w' still allowed)"; continue; fi
    say "------------------------------------------------------------"; if test_one "$w"; then :; else warn "$w graphics test failed; stock was restored"; fi
  done
  say "graphics scan complete; run ./bc250-gfx-probe.sh summary"
}

recover(){
  need_root; prepare_state; lock_probe; check_bc250; check_deps; check_no_persistence
  if [ ! -e "$PENDING" ]; then say "no pending graphics marker; restoring stock anyway"; restore_stock; return; fi
  local w old now phase status log="$LOG_DIR/gfx-recover-$(date +%Y%m%d-%H%M%S).log"
  w="$(sed -n 's/^wgp=//p' "$PENDING" | head -1)"; old="$(sed -n 's/^boot_id=//p' "$PENDING" | head -1)"; phase="$(sed -n 's/^phase=//p' "$PENDING" | head -1)"; now="$(boot_id)"
  if [ -n "$old" ] && [ "$old" != "$now" ]; then status=HANG_OR_REBOOT; else status=INTERRUPTED; fi
  restore_stock >>"$log" 2>&1 || true; append_result "${w:-UNKNOWN}" "$status" "phase=${phase:-unknown}" "$log"; clear_pending; say "${w:-UNKNOWN} => $status; restored stock"
}

summary(){
  prepare_state; printf 'WGP\tGFX_LATEST\tTIME\tDETAIL\n'
  awk -F'\t' '$3!="BASELINE"{s[$3]=$4;t[$3]=$1;d[$3]=$5} END{for(w in s) printf "%s\t%s\t%s\t%s\n",w,s[w],t[w],d[w]}' "$RESULTS" | sort
  printf '\nReference: %s\n' "$REFERENCE"; [ -f "$REFERENCE" ] && printf 'Reference exists: yes\n' || printf 'Reference exists: no\n'
}

stock(){ need_root; prepare_state; lock_probe; check_bc250; check_deps; restore_stock; say "stock routing restored"; }

cmd="${1:-}"; case "$cmd" in
  preflight) preflight;; baseline) baseline;;
  test) [ "$#" -eq 2 ] || die "test requires SE.SH.WGP"; need_root; prepare_state; lock_probe; check_bc250; check_deps; check_no_persistence; test_one "$2";;
  scan) scan;; recover) recover;; summary) summary;; stock) stock;;
  -h|--help|help|"") usage;; *) usage >&2; die "unknown command: $cmd";; esac
