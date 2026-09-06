#!/usr/bin/env bash
# BC-250 incremental WGP health probe.
# Uses WinnieLV/bc250-cu-live-manager for temporary routing and
# duggasco/bc250-40cu-unlock's Vulkan compute verifier for correctness.
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
VERIFY="${BC250_VERIFY:-$SCRIPT_DIR/../upstream/bc250-40cu-unlock/scripts/bc250-compute-verify.sh}"
SERVICE="bc250-cu-live-manager.service"
RESULTS="$STATE_DIR/gpu-results.tsv"
PENDING="$STATE_DIR/gpu-pending"
LOG_DIR="$STATE_DIR/logs"
LOCK_FILE="$STATE_DIR/gpu.lock"
DENYLIST="$STATE_DIR/gpu-manual-bad.tsv"
VISUAL_RESULTS="$STATE_DIR/gpu-visual-results.tsv"
VISUAL_SECONDS="${BC250_VISUAL_SECONDS:-20}"

# Discovered at runtime from amdgpu's boot CU bitmap via the live-manager dashboard.
# Do NOT assume WGP0-2 are the factory set: some BC-250 boards have irregular harvest maps.
EXTRA_WGPS=()
FACTORY_WGPS=()
TOPOLOGY_FILE="$STATE_DIR/gpu-boot-wgp-map.tsv"
CANONICAL_EXTRA_WGPS=(0.0.3 0.0.4 0.1.3 0.1.4 1.0.3 1.0.4 1.1.3 1.1.4)

# Conservative first-pass workload. Override through environment variables if desired.
QUICK_ELEMENTS="${BC250_QUICK_ELEMENTS:-4194304}"
QUICK_PASSES="${BC250_QUICK_PASSES:-2}"
QUICK_ITERS="${BC250_QUICK_ITERS:-64}"
QUICK_TIMEOUT="${BC250_QUICK_TIMEOUT:-300}"
FINAL_ELEMENTS="${BC250_FINAL_ELEMENTS:-16777216}"
FINAL_PASSES="${BC250_FINAL_PASSES:-3}"
FINAL_ITERS="${BC250_FINAL_ITERS:-64}"
FINAL_TIMEOUT="${BC250_FINAL_TIMEOUT:-900}"
MAX_TEMP_C="${BC250_MAX_TEMP_C:-95}"

ACTIVE_TEST=0
CURRENT_WGP=""
THERMAL_ABORT=0

say() { printf '[bc250-probe] %s\n' "$*"; }
warn() { printf '[bc250-probe] WARNING: %s\n' "$*" >&2; }
die() { printf '[bc250-probe] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  sudo ./bc250-gpu-probe.sh preflight
  sudo ./bc250-gpu-probe.sh baseline
  sudo ./bc250-gpu-probe.sh test SE.SH.WGP
  sudo ./bc250-gpu-probe.sh scan
  sudo ./bc250-gpu-probe.sh recover
  sudo ./bc250-gpu-probe.sh summary
  sudo ./bc250-gpu-probe.sh visual-test SE.SH.WGP
  sudo ./bc250-gpu-probe.sh visual-scan
  sudo ./bc250-gpu-probe.sh mark-graphics-fail SE.SH.WGP [reason]
  sudo ./bc250-gpu-probe.sh unmark-graphics-fail SE.SH.WGP
  sudo ./bc250-gpu-probe.sh apply-passed
  sudo ./bc250-gpu-probe.sh stock

Recommended order: preflight -> baseline -> scan -> visual-scan -> summary -> apply-passed.

Safety model:
- no boot persistence is created;
- every candidate is enabled only on top of the factory 24-CU map;
- stock routing is restored after each responsive test;
- a pending marker is synced before each risky write, so a reboot/freeze can be attributed;
- visual-test enables one compute-PASS WGP for a timed real-desktop check, restores stock, then asks what you saw;
- apply-passed requires BOTH compute PASS and PASS_VISUAL, then performs a combined full verifier.

Environment knobs:
  BC250_MANAGER, BC250_VERIFY, BC250_STATE_DIR
  BC250_QUICK_ELEMENTS/PASSES/ITERS/TIMEOUT
  BC250_FINAL_ELEMENTS/PASSES/ITERS/TIMEOUT
  BC250_MAX_TEMP_C (default 95)
  BC250_VISUAL_SECONDS (default 20)
USAGE
}

need_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || die "run as root (sudo)"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

discover_wgp_topology() {
  # The manager marks boot-driver WGPs as D+/D! and non-driver WGPs as S+/--.
  # Capture status through a pipe so ANSI styling is disabled.
  local out line row cell se sh w c0 c1 c2 c3 c4
  local -a parsed=()

  out="$("$MANAGER" status)" || die "could not read BC-250 WGP topology from live-manager"
  mapfile -t parsed < <(
    printf '%s\n' "$out" |
      awk -F'|' '
        $2 ~ /SE[01]\.SH[01]/ {
          row=$2
          gsub(/[[:space:]]/, "", row)
          printf "%s", row
          for (i=3; i<=7; i++) {
            cell=$i
            gsub(/[[:space:]]/, "", cell)
            printf "\t%s", cell
          }
          printf "\n"
        }
      '
  )

  [ "${#parsed[@]}" -eq 4 ] || die "could not parse all four SE/SH rows from live-manager status"

  FACTORY_WGPS=()
  EXTRA_WGPS=()
  for line in "${parsed[@]}"; do
    IFS=$'\t' read -r row c0 c1 c2 c3 c4 <<<"$line"
    [[ "$row" =~ ^SE([01])\.SH([01])$ ]] || die "unexpected topology row: $row"
    se="${BASH_REMATCH[1]}"
    sh="${BASH_REMATCH[2]}"
    for w in 0 1 2 3 4; do
      case "$w" in
        0) cell="$c0" ;; 1) cell="$c1" ;; 2) cell="$c2" ;; 3) cell="$c3" ;; 4) cell="$c4" ;;
      esac
      case "$cell" in
        D+|D!) FACTORY_WGPS+=("$se.$sh.$w") ;;
        S+|--) EXTRA_WGPS+=("$se.$sh.$w") ;;
        *) die "unexpected live-manager cell '$cell' for SE$se.SH$sh WGP$w" ;;
      esac
    done
  done

  [ "${#FACTORY_WGPS[@]}" -eq 12 ] ||
    die "expected 12 boot-driver WGPs (24 CUs), detected ${#FACTORY_WGPS[@]}: ${FACTORY_WGPS[*]}"
  [ "${#EXTRA_WGPS[@]}" -eq 8 ] ||
    die "expected 8 non-driver WGPs (16 CUs), detected ${#EXTRA_WGPS[@]}: ${EXTRA_WGPS[*]}"

  if [ -d "$STATE_DIR" ]; then
    {
      printf '# kind\twgp\n'
      for w in "${FACTORY_WGPS[@]}"; do printf 'factory\t%s\n' "$w"; done
      for w in "${EXTRA_WGPS[@]}"; do printf 'candidate\t%s\n' "$w"; done
    } >"$TOPOLOGY_FILE.tmp"
    mv -f "$TOPOLOGY_FILE.tmp" "$TOPOLOGY_FILE"
    sync "$TOPOLOGY_FILE" 2>/dev/null || true
  fi
}

topology_is_canonical() {
  local i
  [ "${#EXTRA_WGPS[@]}" -eq "${#CANONICAL_EXTRA_WGPS[@]}" ] || return 1
  for i in "${!EXTRA_WGPS[@]}"; do
    [ "${EXTRA_WGPS[$i]}" = "${CANONICAL_EXTRA_WGPS[$i]}" ] || return 1
  done
}

is_extra_wgp() {
  local w="$1" x
  [ "${#EXTRA_WGPS[@]}" -gt 0 ] || discover_wgp_topology
  for x in "${EXTRA_WGPS[@]}"; do [ "$x" = "$w" ] && return 0; done
  return 1
}

boot_id() { cat /proc/sys/kernel/random/boot_id; }

prepare_state() {
  mkdir -p "$STATE_DIR" "$LOG_DIR"
  touch "$RESULTS" "$DENYLIST" "$VISUAL_RESULTS"
  chmod 0700 "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
}

lock_probe() {
  need_cmd flock
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "another bc250-gpu-probe process is already running"
}

check_bc250() {
  need_cmd lspci
  lspci -Dnn | grep -Eqi '\[1002:13fe\]' || die "AMD BC-250 PCI ID 1002:13fe not detected"
}

check_upstream() {
  [ -x "$MANAGER" ] || die "live manager not found/executable: $MANAGER (run ./setup.sh first)"
  [ -x "$VERIFY" ] || die "compute verifier not found/executable: $VERIFY (run ./setup.sh first)"
  need_cmd glslangValidator
  need_cmd gcc
  need_cmd timeout
  need_cmd setsid
}

check_no_persistence() {
  if systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
    die "$SERVICE is enabled. Disable boot restore before probing: sudo systemctl disable --now $SERVICE"
  fi

  local hits=""
  hits+="$(grep -RhsE '(^|[[:space:]])(options[[:space:]]+amdgpu.*)?(bc250_cc_write_mode|disable_cu)=' /etc/modprobe.d 2>/dev/null || true)"
  if grep -Eq '(^|[[:space:]])amdgpu\.(disable_cu|bc250_cc_write_mode)=' /proc/cmdline 2>/dev/null; then
    hits+=$'\n'"$(cat /proc/cmdline)"
  fi
  if [ -n "${hits//$'\n'/}" ]; then
    printf '%s\n' "$hits" >&2
    die "found an old CU override in modprobe/kernel parameters. Remove/disable it and reboot to a clean stock map before this test"
  fi

  # If a patched amdgpu exposes the parameter and it is actively forcing writes, refuse.
  if [ -r /sys/module/amdgpu/parameters/bc250_cc_write_mode ]; then
    local mode
    mode="$(tr -d '[:space:]' </sys/module/amdgpu/parameters/bc250_cc_write_mode 2>/dev/null || true)"
    case "$mode" in
      ""|0) ;;
      *) die "amdgpu bc250_cc_write_mode=$mode is active; boot without it before live probing" ;;
    esac
  fi
}

manager() { "$MANAGER" --yes "$@"; }
restore_stock() {
  say "restoring boot-driver WGP routing"
  manager stock-dispatch
}

max_amdgpu_temp_c() {
  local hw f raw max=""
  for hw in /sys/class/drm/card*/device/hwmon/hwmon*; do
    [ -r "$hw/name" ] || continue
    grep -q '^amdgpu$' "$hw/name" 2>/dev/null || continue
    for f in "$hw"/temp*_input; do
      [ -r "$f" ] || continue
      raw="$(cat "$f" 2>/dev/null || true)"
      [[ "$raw" =~ ^[0-9]+$ ]] || continue
      raw=$((raw / 1000))
      if [ -z "$max" ] || [ "$raw" -gt "$max" ]; then max="$raw"; fi
    done
  done
  [ -n "$max" ] && printf '%s\n' "$max"
}

kernel_log_since() {
  local epoch="$1"
  journalctl -k --since "@$epoch" --no-pager -o short-monotonic 2>/dev/null || true
}

kernel_faults() {
  grep -Ei 'amdgpu.*(ring .*timeout|GPU reset|GPU fault|VM fault|VM_L2_PROTECTION_FAULT|RAS.*error|GPU recovery|amdgpu_job_timedout)|\[Hardware Error\]|Machine check' || true
}


append_visual_result() {
  local wgp="$1" status="$2" detail="$3" logfile="${4:--}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Iseconds)" "$(boot_id)" "$wgp" "$status" "$detail" "$logfile" >>"$VISUAL_RESULTS"
  sync "$VISUAL_RESULTS" 2>/dev/null || true
}

latest_compute_status() {
  local w="$1"
  awk -F'\t' -v w="$w" '$3==w{s=$4} END{print s}' "$RESULTS"
}

latest_visual_status() {
  local w="$1"
  awk -F'\t' -v w="$w" '$3==w{s=$4} END{print s}' "$VISUAL_RESULTS"
}

record_denylist() {
  local wgp="$1" reason="$2" tmp="$DENYLIST.tmp"
  awk -F'\t' -v w="$wgp" '$1!=w' "$DENYLIST" >"$tmp" || true
  printf '%s\t%s\t%s\n' "$wgp" "$(date -Iseconds)" "$reason" >>"$tmp"
  mv -f "$tmp" "$DENYLIST"
  sync "$DENYLIST" 2>/dev/null || true
}

visual_window() {
  local wgp="$1" logfile="$2" remaining t
  say "VISUAL CHECK: ${wgp} is active for ${VISUAL_SECONDS}s."
  say "Use Plasma normally now: move the mouse quickly, open/close menus, move windows, minimize/maximize."
  say "Watch for blue squares, flashes, blocks, lines or other corruption. Do not answer until stock has been restored."
  for ((remaining=VISUAL_SECONDS; remaining>0; remaining--)); do
    t="$(max_amdgpu_temp_c || true)"
    [ -n "$t" ] && printf '[visual-temp] %s C\n' "$t" >>"$logfile"
    if [ -n "$t" ] && [ "$t" -ge "$MAX_TEMP_C" ]; then
      warn "GPU reached ${t}C during visual check (limit ${MAX_TEMP_C}C); stopping early"
      return 2
    fi
    if (( remaining == VISUAL_SECONDS || remaining == 10 || remaining == 5 )); then
      say "visual window: ${remaining}s remaining"
    fi
    sleep 1
  done
  return 0
}

visual_test_one() {
  local wgp="$1" cst stamp logfile vrc answer status detail
  discover_wgp_topology
  is_extra_wgp "$wgp" || die "$wgp is not one of this board's boot-map-disabled WGPs: ${EXTRA_WGPS[*]}"
  [ ! -e "$PENDING" ] || die "pending marker exists; run recover first"
  cst="$(latest_compute_status "$wgp")"
  [ "$cst" = PASS ] || die "$wgp latest compute status is '${cst:-NONE}', not PASS; do not visually exercise a compute-failing WGP"

  while :; do
    stamp="$(date +%Y%m%d-%H%M%S)"
    logfile="$LOG_DIR/visual-${wgp//./_}-$stamp.log"
    restore_stock >>"$logfile" 2>&1
    write_pending "$wgp" "before-visual-enable"
    ACTIVE_TEST=1; CURRENT_WGP="$wgp"
    say "enabling $wgp (+2 CUs) for real-desktop visual validation"
    manager enable-wgp "$wgp" >>"$logfile" 2>&1
    write_pending "$wgp" "enabled-manual-visual-check"
    "$MANAGER" status >>"$logfile" 2>&1 || true

    if visual_window "$wgp" "$logfile"; then vrc=0; else vrc=$?; fi

    # Always restore stock BEFORE asking the operator to classify what they saw.
    if ! restore_stock >>"$logfile" 2>&1; then
      append_visual_result "$wgp" FAIL_RESTORE "stock restore failed after visual window" "$logfile"
      append_result "$wgp" FAIL_RESTORE "stock restore failed after visual window" "$logfile"
      ACTIVE_TEST=0; CURRENT_WGP=""
      die "could not restore stock after visual test; reboot before continuing"
    fi
    ACTIVE_TEST=0; CURRENT_WGP=""
    clear_pending

    if [ "$vrc" -eq 2 ]; then
      status=FAIL_THERMAL; detail="thermal cutoff during manual visual check"
      append_visual_result "$wgp" "$status" "$detail" "$logfile"
      say "$wgp => $status ($detail)"
      return 1
    fi

    while :; do
      printf '\n[bc250-probe] Stock 24-CU routing has been restored.\n' >/dev/tty
      printf '[bc250-probe] Did you see ANY visual corruption while %s was active? [y]es / [n]o / [r]etest / [?] unsure: ' "$wgp" >/dev/tty
      IFS= read -r answer </dev/tty || answer='?'
      case "${answer,,}" in
        y|yes|s|si|sí)
          status=FAIL_VISUAL; detail="operator observed visual corruption during real-desktop check"
          append_visual_result "$wgp" "$status" "$detail" "$logfile"
          record_denylist "$wgp" "$detail"
          append_result "$wgp" FAIL_GRAPHICS "$detail" "$logfile"
          say "$wgp => FAIL_VISUAL; added to persistent denylist"
          return 1
          ;;
        n|no)
          status=PASS_VISUAL; detail="operator observed no artifacts during ${VISUAL_SECONDS}s real-desktop check"
          append_visual_result "$wgp" "$status" "$detail" "$logfile"
          say "$wgp => PASS_VISUAL"
          return 0
          ;;
        r|retest|repeat|repetir)
          append_visual_result "$wgp" RETEST_REQUESTED "operator requested another visual pass" "$logfile"
          say "repeating $wgp visual check"
          break
          ;;
        \?|u|unsure|duda|no-se|nose)
          status=INCONCLUSIVE_VISUAL; detail="operator unsure; not approved and not denylisted"
          append_visual_result "$wgp" "$status" "$detail" "$logfile"
          say "$wgp => INCONCLUSIVE_VISUAL (will NOT be included by apply-passed)"
          return 1
          ;;
        *) printf '[bc250-probe] Please answer y/n/r/?.\n' >/dev/tty ;;
      esac
    done
  done
}

visual_scan_all() {
  need_root; prepare_state; lock_probe; check_bc250; check_upstream; check_no_persistence
  [ ! -e "$PENDING" ] || die "pending marker exists; run recover first"
  discover_wgp_topology
  local w cst vst
  say "manual visual scan; each compute-PASS candidate will be enabled alone on top of stock"
  for w in "${EXTRA_WGPS[@]}"; do
    cst="$(latest_compute_status "$w")"
    vst="$(latest_visual_status "$w")"
    if is_denied_wgp "$w"; then
      say "skipping $w: persistent denylist"
      continue
    fi
    if [ "$cst" != PASS ]; then
      say "skipping $w: compute latest=${cst:-NONE}"
      continue
    fi
    case "$vst" in
      PASS_VISUAL|FAIL_VISUAL) say "skipping $w: visual latest=$vst (use visual-test $w to retest explicitly)"; continue ;;
    esac
    say "------------------------------------------------------------"
    visual_test_one "$w" || true
  done
  say "visual scan complete; run '$0 summary'"
}

append_result() {
  local wgp="$1" status="$2" detail="$3" logfile="$4"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Iseconds)" "$(boot_id)" "$wgp" "$status" "$detail" "$logfile" >>"$RESULTS"
  sync "$RESULTS" 2>/dev/null || sync
}

write_pending() {
  local wgp="$1" phase="$2"
  cat >"$PENDING" <<EOF2
wgp=$wgp
phase=$phase
boot_id=$(boot_id)
time=$(date -Iseconds)
EOF2
  sync "$PENDING" 2>/dev/null || sync
}

clear_pending() { rm -f "$PENDING"; sync "$STATE_DIR" 2>/dev/null || true; }

run_guarded_verifier() {
  local logfile="$1" seconds="$2" elements="$3" passes="$4" iters="$5"
  local pid rc t
  THERMAL_ABORT=0

  say "verifier: elements=$elements passes=$passes iters=$iters; thermal cutoff=${MAX_TEMP_C}C"
  setsid timeout --signal=TERM --kill-after=10s "${seconds}s" \
    "$VERIFY" --elements "$elements" --passes "$passes" --iters "$iters" \
    >>"$logfile" 2>&1 &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    t="$(max_amdgpu_temp_c || true)"
    if [ -n "$t" ]; then
      printf '[temp] %s C\n' "$t" >>"$logfile"
      if [ "$t" -ge "$MAX_TEMP_C" ]; then
        THERMAL_ABORT=1
        warn "GPU hwmon reached ${t}C (limit ${MAX_TEMP_C}C); terminating verifier"
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -KILL -- "-$pid" 2>/dev/null || true
        break
      fi
    fi
    sleep 1
  done

  if wait "$pid"; then rc=0; else rc=$?; fi
  return "$rc"
}

cleanup_trap() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if [ "$ACTIVE_TEST" -eq 1 ]; then
    warn "abnormal exit while testing ${CURRENT_WGP:-unknown}; attempting stock restore"
    restore_stock >/dev/null 2>&1 || true
    # Keep pending marker on abnormal exit so the operator can inspect/recover it.
  fi
  exit "$rc"
}
trap cleanup_trap EXIT INT TERM HUP

preflight() {
  need_root; prepare_state; lock_probe; check_bc250; check_upstream; check_no_persistence
  say "hardware and dependencies detected"
  say "kernel: $(uname -r)"
  say "manager: $MANAGER"
  say "verifier: $VERIFY"
  "$MANAGER" status
  discover_wgp_topology
  say "boot-driver WGPs: ${FACTORY_WGPS[*]}"
  say "test candidates: ${EXTRA_WGPS[*]}"
  if ! topology_is_canonical; then
    warn "irregular factory harvest map detected; using THIS board's amdgpu boot bitmap instead of the common WGP0-2 template"
  fi
  if [ -e "$PENDING" ]; then
    warn "a pending marker exists from an earlier test:"
    cat "$PENDING" >&2
    warn "run: sudo $0 recover"
  else
    say "no pending crash marker"
  fi
  local t
  t="$(max_amdgpu_temp_c || true)"
  [ -n "$t" ] && say "current maximum amdgpu temperature: ${t}C"
}

run_baseline() {
  need_root; prepare_state; lock_probe; check_bc250; check_upstream; check_no_persistence
  [ ! -e "$PENDING" ] || die "pending marker exists; run recover first"
  discover_wgp_topology
  local stamp logfile epoch rc faults
  stamp="$(date +%Y%m%d-%H%M%S)"
  logfile="$LOG_DIR/gpu-baseline-$stamp.log"
  restore_stock | tee -a "$logfile"
  "$MANAGER" status >>"$logfile" 2>&1 || true
  epoch="$(date +%s)"
  if run_guarded_verifier "$logfile" "$QUICK_TIMEOUT" "$QUICK_ELEMENTS" "$QUICK_PASSES" "$QUICK_ITERS"; then rc=0; else rc=$?; fi
  kernel_log_since "$epoch" >>"$logfile"
  faults="$(kernel_log_since "$epoch" | kernel_faults)"
  if [ "$THERMAL_ABORT" -eq 1 ]; then
    append_result BASELINE FAIL_THERMAL "stock baseline exceeded temp cutoff" "$logfile"
    die "stock baseline hit thermal cutoff; fix cooling/clocks before CU testing"
  elif [ "$rc" -ne 0 ]; then
    append_result BASELINE FAIL_VERIFY "stock verifier rc=$rc" "$logfile"
    die "stock 24-CU baseline failed (rc=$rc); do not attribute later failures to harvested WGPs"
  elif [ -n "$faults" ]; then
    printf '%s\n' "$faults" >>"$logfile"
    append_result BASELINE FAIL_KERNEL "kernel GPU/hardware fault during stock baseline" "$logfile"
    die "stock baseline produced kernel GPU/hardware faults; resolve baseline instability first"
  else
    append_result BASELINE PASS "stock quick verifier clean" "$logfile"
    say "stock 24-CU baseline PASS"
  fi
}

probe_one() {
  local wgp="$1"
  [ "${#EXTRA_WGPS[@]}" -gt 0 ] || discover_wgp_topology
  is_extra_wgp "$wgp" || die "$wgp is not one of this board's eight boot-map-disabled WGPs: ${EXTRA_WGPS[*]}"
  [ ! -e "$PENDING" ] || die "pending marker exists; run recover first"

  local stamp logfile epoch rc faults status detail
  stamp="$(date +%Y%m%d-%H%M%S)"
  logfile="$LOG_DIR/gpu-${wgp//./_}-$stamp.log"

  restore_stock >>"$logfile" 2>&1
  write_pending "$wgp" "before-enable"
  ACTIVE_TEST=1; CURRENT_WGP="$wgp"
  say "enabling candidate WGP $wgp (2 CUs) on top of the boot-driver 24-CU map"
  manager enable-wgp "$wgp" >>"$logfile" 2>&1
  write_pending "$wgp" "enabled-running-verifier"
  "$MANAGER" status >>"$logfile" 2>&1 || true

  epoch="$(date +%s)"
  if run_guarded_verifier "$logfile" "$QUICK_TIMEOUT" "$QUICK_ELEMENTS" "$QUICK_PASSES" "$QUICK_ITERS"; then rc=0; else rc=$?; fi
  kernel_log_since "$epoch" >>"$logfile"
  faults="$(kernel_log_since "$epoch" | kernel_faults)"

  # Restore first; only then mark the test completed and clear the crash marker.
  if ! restore_stock >>"$logfile" 2>&1; then
    append_result "$wgp" FAIL_RESTORE "test returned but stock restore failed; reboot recommended" "$logfile"
    ACTIVE_TEST=0
    die "could not restore stock routing after $wgp; reboot before continuing"
  fi
  ACTIVE_TEST=0; CURRENT_WGP=""

  if [ "$THERMAL_ABORT" -eq 1 ]; then
    status="FAIL_THERMAL"; detail="temperature cutoff reached"
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    status="FAIL_TIMEOUT"; detail="verifier timed out/was killed rc=$rc"
  elif [ "$rc" -ne 0 ]; then
    status="FAIL_VERIFY"; detail="verifier rc=$rc"
  elif [ -n "$faults" ]; then
    status="FAIL_KERNEL"; detail="kernel GPU/hardware fault observed"
    printf '\n--- filtered kernel faults ---\n%s\n' "$faults" >>"$logfile"
  else
    status="PASS"; detail="quick verifier clean"
  fi

  append_result "$wgp" "$status" "$detail" "$logfile"
  clear_pending
  say "$wgp => $status ($detail)"
  [ "$status" = PASS ]
}

scan_all() {
  need_root; prepare_state; lock_probe; check_bc250; check_upstream; check_no_persistence
  [ ! -e "$PENDING" ] || die "pending marker exists; run recover first"
  discover_wgp_topology
  say "using boot-map-disabled candidates: ${EXTRA_WGPS[*]}"
  say "running 24-CU driver-topology baseline first"
  # Inline a compact baseline check without reacquiring the flock.
  local bstamp blog bepoch brc bfaults
  bstamp="$(date +%Y%m%d-%H%M%S)"; blog="$LOG_DIR/gpu-baseline-$bstamp.log"
  restore_stock >>"$blog" 2>&1
  bepoch="$(date +%s)"
  if run_guarded_verifier "$blog" "$QUICK_TIMEOUT" "$QUICK_ELEMENTS" "$QUICK_PASSES" "$QUICK_ITERS"; then brc=0; else brc=$?; fi
  kernel_log_since "$bepoch" >>"$blog"
  bfaults="$(kernel_log_since "$bepoch" | kernel_faults)"
  if [ "$THERMAL_ABORT" -eq 1 ] || [ "$brc" -ne 0 ] || [ -n "$bfaults" ]; then
    append_result BASELINE FAIL "thermal=$THERMAL_ABORT rc=$brc kernel_faults=$([ -n "$bfaults" ] && echo yes || echo no)" "$blog"
    die "stock baseline is not clean; aborting scan"
  fi
  append_result BASELINE PASS "stock quick verifier clean" "$blog"

  local w last
  for w in "${EXTRA_WGPS[@]}"; do
    last="$(awk -F'\t' -v w="$w" '$3==w{s=$4} END{print s}' "$RESULTS")"
    if [ -n "$last" ]; then
      say "skipping already-classified $w (latest=$last); use '$0 test $w' to retest it explicitly"
      continue
    fi
    say "------------------------------------------------------------"
    if probe_one "$w"; then :; else warn "$w failed; continuing with next WGP because stock routing was restored"; fi
  done
  say "scan complete; use '$0 summary'"
}

recover() {
  need_root; prepare_state; lock_probe; check_bc250; check_upstream; check_no_persistence
  if [ ! -e "$PENDING" ]; then
    say "no pending marker; restoring stock anyway"
    restore_stock
    return 0
  fi
  local wgp oldboot phase nowboot logfile status
  wgp="$(sed -n 's/^wgp=//p' "$PENDING" | head -n1)"
  oldboot="$(sed -n 's/^boot_id=//p' "$PENDING" | head -n1)"
  phase="$(sed -n 's/^phase=//p' "$PENDING" | head -n1)"
  nowboot="$(boot_id)"
  logfile="$LOG_DIR/recover-$(date +%Y%m%d-%H%M%S).log"

  if [ -n "$oldboot" ] && [ "$oldboot" != "$nowboot" ]; then
    status="HANG_OR_REBOOT"
    say "pending $wgp came from another boot; treating it as a hard hang/reboot candidate"
  else
    status="INTERRUPTED"
    say "pending $wgp is from this boot; treating it as an interrupted test"
  fi
  restore_stock | tee -a "$logfile"
  append_result "${wgp:-UNKNOWN}" "$status" "pending phase=${phase:-unknown}; recovered to stock" "$logfile"
  case "${phase:-}" in *visual*) append_visual_result "${wgp:-UNKNOWN}" "$status" "pending phase=${phase:-unknown}; recovered to stock" "$logfile" ;; esac
  clear_pending
  say "recovery recorded: ${wgp:-UNKNOWN} => $status"
}

latest_statuses() {
  awk -F'\t' '
    $3 != "BASELINE" { status[$3]=$4; detail[$3]=$5; time[$3]=$1 }
    END { for (w in status) printf "%s\t%s\t%s\t%s\n", w, status[w], time[w], detail[w] }
  ' "$RESULTS" | sort
}

summary() {
  prepare_state
  printf 'WGP\tLATEST\tTIME\tDETAIL\n'
  latest_statuses
  if [ -r "$TOPOLOGY_FILE" ]; then
    mapfile -t FACTORY_WGPS < <(awk -F'\t' '$1=="factory"{print $2}' "$TOPOLOGY_FILE")
    mapfile -t EXTRA_WGPS < <(awk -F'\t' '$1=="candidate"{print $2}' "$TOPOLOGY_FILE")
    printf '\nBoot-driver WGP set: %s\n' "${FACTORY_WGPS[*]}"
    printf 'Boot-map-disabled candidates: %s\n' "${EXTRA_WGPS[*]}"
  else
    printf '\nBoot WGP map not cached yet; run preflight first.\n'
  fi
  printf 'Each candidate WGP = 2 CUs. Boot topology = 24 CUs; each PASS candidate adds 2 CUs.\n'
  printf '\nVISUAL VALIDATION (latest):\nWGP\tVISUAL_LATEST\tTIME\tDETAIL\n'
  awk -F'\t' '$3!="BASELINE"{s[$3]=$4;t[$3]=$1;d[$3]=$5} END{for(w in s) printf "%s\t%s\t%s\t%s\n",w,s[w],t[w],d[w]}' "$VISUAL_RESULTS" | sort
  if [ -s "$DENYLIST" ]; then
    printf '\nMANUAL GRAPHICS DENYLIST (always excluded by apply-passed):\n'
    awk -F'\t' '{printf "%s\t%s\t%s\n",$1,$2,$3}' "$DENYLIST"
  fi
  if [ -e "$PENDING" ]; then
    printf '\nPENDING CRASH MARKER:\n'
    cat "$PENDING"
  fi
}

is_denied_wgp() {
  local w="$1"
  awk -F'\t' -v w="$w" '$1==w{found=1} END{exit !found}' "$DENYLIST" 2>/dev/null
}

mark_graphics_fail() {
  need_root; prepare_state; lock_probe; check_bc250; check_upstream
  local wgp="${1:-}" reason="${2:-manual visual artifacts observed}" tmp
  [ -n "$wgp" ] || die "usage: $0 mark-graphics-fail SE.SH.WGP [reason]"
  discover_wgp_topology
  is_extra_wgp "$wgp" || die "$wgp is not one of this board's boot-map-disabled WGPs: ${EXTRA_WGPS[*]}"
  record_denylist "$wgp" "$reason"
  append_visual_result "$wgp" FAIL_VISUAL "$reason" "-"
  append_result "$wgp" FAIL_GRAPHICS "$reason" "-"
  say "$wgp => FAIL_GRAPHICS ($reason)"
  say "persistent manual denylist updated; later PASS tests will NOT make apply-passed include it"
}

unmark_graphics_fail() {
  need_root; prepare_state; lock_probe; check_bc250
  local wgp="${1:-}" tmp
  [ -n "$wgp" ] || die "usage: $0 unmark-graphics-fail SE.SH.WGP"
  tmp="$DENYLIST.tmp"
  awk -F'\t' -v w="$wgp" '$1!=w' "$DENYLIST" >"$tmp" || true
  mv -f "$tmp" "$DENYLIST"; sync "$DENYLIST" 2>/dev/null || true
  say "$wgp removed from manual denylist (this does not erase historical results)"
}

passed_wgps() {
  local w st vst
  for w in "${EXTRA_WGPS[@]}"; do
    if is_denied_wgp "$w"; then
      say "excluding manually denied WGP $w" >&2
      continue
    fi
    st="$(latest_compute_status "$w")"
    vst="$(latest_visual_status "$w")"
    if [ "$st" = PASS ] && [ "$vst" = PASS_VISUAL ]; then
      printf '%s\n' "$w"
    elif [ "$st" = PASS ]; then
      say "excluding $w: compute PASS but visual latest=${vst:-NONE} (need PASS_VISUAL)" >&2
    fi
  done
}

apply_passed() {
  need_root; prepare_state; lock_probe; check_bc250; check_upstream; check_no_persistence
  [ ! -e "$PENDING" ] || die "pending marker exists; run recover first"
  discover_wgp_topology
  mapfile -t good < <(passed_wgps)
  [ "${#good[@]}" -gt 0 ] || die "no WGP has both compute PASS and PASS_VISUAL"

  local stamp logfile epoch rc faults expected
  expected=$((24 + 2 * ${#good[@]}))
  logfile="$LOG_DIR/gpu-combined-${expected}cu-$(date +%Y%m%d-%H%M%S).log"
  say "candidate combined set: ${good[*]} => nominal ${expected} CUs"
  restore_stock >>"$logfile" 2>&1
  write_pending "COMBINED:${good[*]}" "before-combined-enable"
  ACTIVE_TEST=1; CURRENT_WGP="COMBINED"
  manager enable-wgp "${good[@]}" >>"$logfile" 2>&1
  write_pending "COMBINED:${good[*]}" "combined-running-final-verifier"
  "$MANAGER" status >>"$logfile" 2>&1 || true

  epoch="$(date +%s)"
  if run_guarded_verifier "$logfile" "$FINAL_TIMEOUT" "$FINAL_ELEMENTS" "$FINAL_PASSES" "$FINAL_ITERS"; then rc=0; else rc=$?; fi
  kernel_log_since "$epoch" >>"$logfile"
  faults="$(kernel_log_since "$epoch" | kernel_faults)"

  if [ "$THERMAL_ABORT" -eq 1 ] || [ "$rc" -ne 0 ] || [ -n "$faults" ]; then
    warn "combined set failed final validation; restoring stock"
    restore_stock >>"$logfile" 2>&1 || true
    ACTIVE_TEST=0; CURRENT_WGP=""
    append_result COMBINED FAIL "${expected}CU thermal=$THERMAL_ABORT rc=$rc kernel_faults=$([ -n "$faults" ] && echo yes || echo no)" "$logfile"
    clear_pending
    die "combined validation failed; stock routing restored"
  fi

  # Compute passed. Exercise the combined set on the real desktop before approving it.
  write_pending "COMBINED:${good[*]}" "combined-manual-visual-check"
  local cvrc answer
  if visual_window "COMBINED-${expected}CU" "$logfile"; then cvrc=0; else cvrc=$?; fi

  # Restore before asking, exactly as in the individual visual test.
  if ! restore_stock >>"$logfile" 2>&1; then
    ACTIVE_TEST=0; CURRENT_WGP=""
    append_result COMBINED FAIL_RESTORE "${expected}CU stock restore failed after combined visual window" "$logfile"
    die "combined compute passed but stock restore failed after visual window; reboot"
  fi
  ACTIVE_TEST=0; CURRENT_WGP=""

  if [ "$cvrc" -eq 2 ]; then
    append_result COMBINED FAIL_THERMAL "${expected}CU thermal cutoff during combined visual check" "$logfile"
    clear_pending
    die "combined set hit thermal cutoff during visual validation; stock restored"
  fi

  while :; do
    printf '\n[bc250-probe] Stock 24-CU routing has been restored after the combined test.\n' >/dev/tty
    printf '[bc250-probe] Did you see ANY visual corruption with the combined %s-CU set? [y]es / [n]o / [?] unsure: ' "$expected" >/dev/tty
    IFS= read -r answer </dev/tty || answer='?'
    case "${answer,,}" in
      y|yes|s|si|sí)
        append_result COMBINED FAIL_GRAPHICS "${expected}CU combined compute clean but operator observed visual corruption" "$logfile"
        clear_pending
        die "combined visual validation failed; stock routing remains active"
        ;;
      n|no)
        say "combined visual validation PASS; re-enabling approved set"
        manager enable-wgp "${good[@]}" >>"$logfile" 2>&1
        append_result COMBINED PASS "${expected}CU combined compute + manual visual validation clean; left active live (NOT persistent)" "$logfile"
        clear_pending
        say "combined ${expected}-CU routing PASS and is currently active live"
        say "it will disappear on reboot because this script never installs a boot-restore service"
        say "before making it persistent, test real games/workloads for longer; this validation is strong but not exhaustive"
        break
        ;;
      \?|u|unsure|duda|no-se|nose)
        append_result COMBINED INCONCLUSIVE_VISUAL "${expected}CU combined compute clean; operator unsure visually" "$logfile"
        clear_pending
        die "combined visual result inconclusive; stock routing remains active"
        ;;
      *) printf '[bc250-probe] Please answer y/n/?.\n' >/dev/tty ;;
    esac
  done
}

stock_cmd() {
  need_root; prepare_state; lock_probe; check_bc250; check_upstream
  restore_stock
  if [ -e "$PENDING" ]; then
    warn "pending crash marker was NOT erased; run '$0 recover' to preserve attribution"
  fi
}

cmd="${1:-}"
case "$cmd" in
  preflight) preflight ;;
  baseline) run_baseline ;;
  test) [ "$#" -eq 2 ] || die "test requires one WGP, e.g. 0.0.3"; need_root; prepare_state; lock_probe; check_bc250; check_upstream; check_no_persistence; probe_one "$2" ;;
  scan) scan_all ;;
  recover) recover ;;
  summary) summary ;;
  visual-test) [ "$#" -eq 2 ] || die "visual-test requires one WGP, e.g. 0.0.3"; need_root; prepare_state; lock_probe; check_bc250; check_upstream; check_no_persistence; visual_test_one "$2" ;;
  visual-scan) visual_scan_all ;;
  mark-graphics-fail) shift; mark_graphics_fail "${1:-}" "${2:-manual visual artifacts observed}" ;;
  unmark-graphics-fail) shift; unmark_graphics_fail "${1:-}" ;;
  apply-passed) apply_passed ;;
  stock) stock_cmd ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; die "unknown command: $cmd" ;;
esac
