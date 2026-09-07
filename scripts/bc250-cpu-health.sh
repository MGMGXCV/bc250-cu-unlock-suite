#!/usr/bin/env bash
# BC-250 CPU unlock + validation + optional boot re-arm helper.
# The actual SMU 0x77 -> 0xFF operation is delegated to bc250-cu-live-manager.
# This script deliberately does NOT invent arbitrary CPU masks.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bc250-platform.sh
source "$SCRIPT_DIR/bc250-platform.sh"
PLATFORM="$(bc250_detect_platform)"
if [ -n "${BC250_STATE_DIR:-}" ]; then
  STATE_DIR="$BC250_STATE_DIR"
elif [ "$PLATFORM" = steamos ]; then
  STATE_DIR="$(bc250_steamos_state_dir)"
else
  STATE_DIR="/var/lib/bc250-probe"
fi
MANAGER="${BC250_MANAGER:-$SCRIPT_DIR/../upstream/bc250-cu-live-manager/bc250-cu-live-manager.sh}"
LOG_DIR="$STATE_DIR/logs"
RESULTS="$STATE_DIR/cpu-results.tsv"
NEW_CORE_IDS=(3 7) # stock mask 0x77 has physical cores 3 and 7 disabled.
MAX_TEMP_C="${BC250_MAX_TEMP_C:-95}"

REARM_SERVICE="${BC250_CPU_REARM_SERVICE:-bc250-cpu-rearm.service}"
REARM_UNIT="${BC250_CPU_REARM_UNIT:-/etc/systemd/system/$REARM_SERVICE}"
if [ "$PLATFORM" = steamos ]; then
  REARM_MANAGER="${BC250_CPU_REARM_MANAGER:-/opt/bc250-wgp-lab/bin/bc250-cpu-rearm-manager}"
  REARM_KEEP_FILE="${BC250_CPU_REARM_KEEP_FILE:-/etc/atomic-update.conf.d/bc250-cpu-rearm.conf}"
else
  REARM_MANAGER="${BC250_CPU_REARM_MANAGER:-/usr/local/libexec/bc250-cu-unlock-suite/bc250-cpu-rearm-manager}"
  REARM_KEEP_FILE="${BC250_CPU_REARM_KEEP_FILE:-}"
fi

say() { printf '[bc250-cpu] %s\n' "$*"; }
warn() { printf '[bc250-cpu] WARNING: %s\n' "$*" >&2; }
die() { printf '[bc250-cpu] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  sudo ./bc250-cpu-health.sh status
  sudo ./bc250-cpu-health.sh unlock
  sudo ./bc250-cpu-health.sh quick
  sudo ./bc250-cpu-health.sh deep
  sudo ./bc250-cpu-health.sh rearm status
  sudo ./bc250-cpu-health.sh rearm enable
  sudo ./bc250-cpu-health.sh rearm disable

unlock: delegates the volatile 0x77 -> 0xFF SMU operation to bc250-cu-live-manager.
        It NEVER reboots automatically. Use a normal warm reboot afterwards.
quick : tests physical cores 3 and 7 for 30 s each, then all threads for 60 s.
deep  : tests physical cores 3 and 7 for 300 s each, then all threads for 600 s.

Automatic CPU re-arm is ADVANCED and OFF by default.
When enabled, a systemd oneshot re-runs the safe 0x77 -> 0xFF unlock after a cold
boot. This only saves you from manually running 'cpu unlock'. The current cold-boot
session remains 6c/12t until YOU choose to perform one warm reboot. The service
never reboots the machine automatically.

Re-arm enable is refused until one complete 'deep' run has PASS records for core3,
core7 and ALL in the same test log. Real workloads are still recommended.

A full cold power removal returns the CPU core mask to factory state on the
volatile method. If 8-core POST/boot is unstable, remove power completely to recover.
USAGE
}

need_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || die "run as root (sudo)"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
prepare() { mkdir -p "$STATE_DIR" "$LOG_DIR"; touch "$RESULTS"; chmod 0700 "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true; }
check_bc250() { need_cmd lspci; lspci -Dnn | grep -Eqi '\[1002:13fe\]' || die "BC-250 PCI ID 1002:13fe not detected"; }
check_manager() { [ -x "$MANAGER" ] || die "live manager missing: $MANAGER (run ./setup.sh first)"; }

present_threads() {
  local p part lo hi n=0
  local -a parts
  p="$(cat /sys/devices/system/cpu/present)"
  IFS=',' read -ra parts <<<"$p"
  for part in "${parts[@]}"; do
    if [[ "$part" == *-* ]]; then lo="${part%-*}"; hi="${part#*-}"; n=$((n + hi - lo + 1)); else n=$((n + 1)); fi
  done
  printf '%s\n' "$n"
}

max_amdgpu_temp_c() {
  local hw f raw max=""
  for hw in /sys/class/drm/card*/device/hwmon/hwmon*; do
    [ -r "$hw/name" ] || continue
    grep -q '^amdgpu$' "$hw/name" 2>/dev/null || continue
    for f in "$hw"/temp*_input; do
      [ -r "$f" ] || continue
      raw="$(cat "$f" 2>/dev/null || true)"; [[ "$raw" =~ ^[0-9]+$ ]] || continue
      raw=$((raw / 1000)); if [ -z "$max" ] || [ "$raw" -gt "$max" ]; then max="$raw"; fi
    done
  done
  [ -n "$max" ] && printf '%s\n' "$max"
}

core_siblings() {
  local wanted="$1" cpu d core list=""
  for d in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -r "$d/topology/core_id" ] || continue
    cpu="${d##*cpu}"; core="$(cat "$d/topology/core_id")"
    [ "$core" = "$wanted" ] || continue
    list="${list}${list:+,}$cpu"
  done
  [ -n "$list" ] && printf '%s\n' "$list"
}

csv_count() { awk -F',' '{print NF}' <<<"$1"; }

kernel_faults_since() {
  local epoch="$1"
  journalctl -k --since "@$epoch" --no-pager 2>/dev/null | \
    grep -Ei '\[Hardware Error\]|Machine check|mce:|EDAC.*error|watchdog:.*lockup' || true
}

append_result() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$1" "$2" "$3" "$4" >>"$RESULTS"
}

run_core_test() {
  local core="$1" dur="$2" logfile="$3" cpus workers epoch rc faults temp
  cpus="$(core_siblings "$core" || true)"
  [ -n "$cpus" ] || { append_result "core$core" NOT_PRESENT "no logical CPUs mapped" "$logfile"; return 2; }
  workers="$(csv_count "$cpus")"
  say "physical core $core -> logical CPU(s) $cpus; stress-ng verify ${dur}s"
  epoch="$(date +%s)"
  if timeout --signal=TERM --kill-after=5s "$((dur + 30))s" \
      taskset -c "$cpus" stress-ng --cpu "$workers" --cpu-method all --verify --metrics-brief --timeout "${dur}s" \
      >>"$logfile" 2>&1; then rc=0; else rc=$?; fi
  faults="$(kernel_faults_since "$epoch")"
  temp="$(max_amdgpu_temp_c || true)"
  [ -n "$temp" ] && printf '[post-test max amdgpu hwmon] %s C\n' "$temp" >>"$logfile"
  if [ "$rc" -ne 0 ]; then
    append_result "core$core" FAIL "stress-ng rc=$rc cpus=$cpus" "$logfile"; return 1
  elif [ -n "$faults" ]; then
    printf '\n--- kernel hardware faults ---\n%s\n' "$faults" >>"$logfile"
    append_result "core$core" FAIL_KERNEL "hardware/MCE log cpus=$cpus" "$logfile"; return 1
  else
    append_result "core$core" PASS "stress-ng --verify clean cpus=$cpus" "$logfile"; return 0
  fi
}

run_all_test() {
  local dur="$1" logfile="$2" epoch rc faults temp n
  n="$(nproc)"; say "all-thread stress-ng verify: $n online threads, ${dur}s"
  epoch="$(date +%s)"
  if timeout --signal=TERM --kill-after=5s "$((dur + 30))s" \
      stress-ng --cpu 0 --cpu-method all --verify --metrics-brief --timeout "${dur}s" \
      >>"$logfile" 2>&1; then rc=0; else rc=$?; fi
  faults="$(kernel_faults_since "$epoch")"; temp="$(max_amdgpu_temp_c || true)"
  [ -n "$temp" ] && printf '[post-test max amdgpu hwmon] %s C\n' "$temp" >>"$logfile"
  if [ -n "$temp" ] && [ "$temp" -ge "$MAX_TEMP_C" ]; then
    warn "post-test APU/GPU hwmon reached ${temp}C; improve cooling or reduce clocks before longer testing"
  fi
  if [ "$rc" -ne 0 ]; then append_result ALL FAIL "stress-ng rc=$rc" "$logfile"; return 1
  elif [ -n "$faults" ]; then printf '\n--- kernel hardware faults ---\n%s\n' "$faults" >>"$logfile"; append_result ALL FAIL_KERNEL "MCE/hardware log" "$logfile"; return 1
  else append_result ALL PASS "all-thread stress-ng --verify clean" "$logfile"; return 0; fi
}

latest_deep_pass_log() {
  awk -F'\t' '$2=="ALL" && $3=="PASS" && $5 ~ /cpu-deep-/ {found=$5} END{print found}' "$RESULTS" 2>/dev/null || true
}

deep_gate_ok() {
  local log stage
  log="$(latest_deep_pass_log)"
  [ -n "$log" ] || return 1
  for stage in core3 core7 ALL; do
    awk -F'\t' -v s="$stage" -v l="$log" '$2==s && $3=="PASS" && $5==l {ok=1} END{exit !ok}' "$RESULTS" || return 1
  done
  return 0
}

rearm_enabled() { systemctl is-enabled --quiet "$REARM_SERVICE" 2>/dev/null; }

print_rearm_summary() {
  local present
  present="$(present_threads)"
  if rearm_enabled; then
    if [ "$present" -ge 16 ]; then
      say "CPU re-arm: ENABLED (advanced); 8c/16t is active"
    elif systemctl is-active --quiet "$REARM_SERVICE" 2>/dev/null; then
      say "CPU re-arm: ENABLED; unlock was re-armed this boot — warm reboot required for 8c/16t"
    elif systemctl is-failed --quiet "$REARM_SERVICE" 2>/dev/null; then
      warn "CPU re-arm: ENABLED but service FAILED; inspect: journalctl -u $REARM_SERVICE -b"
    else
      say "CPU re-arm: ENABLED; service has not completed this boot"
    fi
  else
    say "CPU re-arm: disabled (default)"
  fi
}

status_cmd() {
  need_root; prepare; check_bc250; check_manager
  "$MANAGER" status
  say "kernel-present threads: $(present_threads); online: $(nproc)"
  lscpu | grep -E '^(CPU\(s\)|Core\(s\) per socket|Thread\(s\) per core|Model name):' || true
  print_rearm_summary
  [ -s "$RESULTS" ] && { printf '\nLatest CPU test records:\n'; tail -n 20 "$RESULTS"; }
}

unlock_cmd() {
  need_root; prepare; check_bc250; check_manager
  say "delegating volatile CPU unlock to verified live-manager implementation"
  "$MANAGER" --yes cpu-unlock
  say "if it reported success, perform a WARM reboot when ready: sudo systemctl reboot"
  say "after reboot, verify 16 threads with '$0 status', then run '$0 quick'"
  say "if POST/boot becomes unstable, remove power completely; the volatile mask returns to stock on a cold power cycle"
}

health_cmd() {
  local mode="$1" core_dur all_dur stamp logfile failures=0 core
  case "$mode" in
    quick) core_dur=30; all_dur=60 ;;
    deep) core_dur=300; all_dur=600 ;;
    *) die "unknown health mode" ;;
  esac
  need_root; prepare; check_bc250; need_cmd stress-ng; need_cmd taskset; need_cmd timeout; need_cmd journalctl
  [ "$(present_threads)" -ge 16 ] || die "8 cores are not enumerated (need 16 threads present). Run unlock, warm reboot, then retry"
  stamp="$(date +%Y%m%d-%H%M%S)"; logfile="$LOG_DIR/cpu-$mode-$stamp.log"
  {
    echo "date=$(date -Iseconds)"; echo "kernel=$(uname -r)"; lscpu; echo; cat /proc/cmdline
  } >>"$logfile"

  for core in "${NEW_CORE_IDS[@]}"; do
    if run_core_test "$core" "$core_dur" "$logfile"; then say "core $core PASS"; else warn "core $core FAILED"; failures=$((failures+1)); fi
  done
  if run_all_test "$all_dur" "$logfile"; then say "all-thread PASS"; else warn "all-thread FAILED"; failures=$((failures+1)); fi
  say "log: $logfile"
  if [ "$failures" -ne 0 ]; then
    warn "$failures CPU test stage(s) failed. Do not enable automatic CPU re-arm. Cold-power-cycle back to stock if instability continues."
    return 1
  fi
  if [ "$mode" = deep ]; then
    say "CPU deep health suite PASS. Automatic re-arm safety gate is now satisfied for this test log."
    say "Real games/workloads are still recommended before enabling re-arm."
  else
    say "CPU quick health suite PASS. This is evidence, not a guarantee; run deep plus your real workload before automatic re-arm."
  fi
}

write_steamos_rearm_keep() {
  [ "$PLATFORM" = steamos ] || return 0
  install -d -o root -g root -m 0755 /etc/atomic-update.conf.d
  cat >"$REARM_KEEP_FILE" <<EOF_KEEP
# BC-250 CU Unlock Suite CPU re-arm integration retained across SteamOS atomic updates.
$REARM_UNIT
/etc/systemd/system/multi-user.target.wants/$REARM_SERVICE
$REARM_KEEP_FILE
EOF_KEEP
  chmod 0644 "$REARM_KEEP_FILE"
}

install_rearm_manager_copy() {
  install -D -o root -g root -m 0755 "$MANAGER" "$REARM_MANAGER"
}

write_rearm_unit() {
  cat >"$REARM_UNIT" <<EOF_UNIT
[Unit]
Description=BC-250 CPU unlock re-arm (manual warm reboot required for 8c/16t)
After=bc250-cu-live-manager.service cyan-skillfish-governor-smu.service
ConditionPathExists=/sys/bus/pci/devices/0000:00:00.0/config

[Service]
Type=oneshot
ExecStart=$REARM_MANAGER --yes cpu-unlock
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_UNIT
  chmod 0644 "$REARM_UNIT"
}

rearm_status_cmd() {
  need_root; prepare
  local present deep="NO"
  present="$(present_threads)"
  deep_gate_ok && deep="PASS"
  printf 'CPU threads present : %s\n' "$present"
  printf 'CPU re-arm service  : '
  if rearm_enabled; then printf 'ENABLED\n'; else printf 'disabled (default)\n'; fi
  printf 'Deep safety gate    : %s\n' "$deep"
  printf 'Installed unit      : %s\n' "$REARM_UNIT"
  if rearm_enabled; then
    if [ "$present" -ge 16 ]; then
      printf 'State               : 8c/16t active\n'
    elif systemctl is-active --quiet "$REARM_SERVICE" 2>/dev/null; then
      printf 'State               : re-armed this boot; WARM REBOOT REQUIRED for 8c/16t\n'
    elif systemctl is-failed --quiet "$REARM_SERVICE" 2>/dev/null; then
      printf 'State               : service FAILED (journalctl -u %s -b)\n' "$REARM_SERVICE"
    else
      printf 'State               : enabled; not completed this boot\n'
    fi
    printf '\nImportant: re-arm does NOT make 8c/16t appear during the current cold-boot session.\n'
    printf 'It only avoids running cpu unlock manually. You still choose when to warm reboot.\n'
    printf 'The service never reboots the machine automatically.\n'
  fi
}

rearm_enable_cmd() {
  need_root; prepare; check_bc250; check_manager; need_cmd systemctl
  if rearm_enabled; then
    say "CPU re-arm is already enabled"
    rearm_status_cmd
    return 0
  fi
  if ! deep_gate_ok; then
    die "automatic CPU re-arm requires one complete deep PASS (core3 + core7 + ALL in the same cpu-deep log). Run: sudo ./bc250-unlock cpu deep"
  fi

  say "ADVANCED: automatic CPU re-arm is OFF by default."
  say "It will run the known 0x77 -> 0xFF unlock after each cold boot."
  say "It ONLY saves the manual 'cpu unlock' step; a WARM reboot is still required to activate 8c/16t."
  say "It NEVER reboots automatically. A cold power cycle remains the recovery path."
  local answer
  printf '[bc250-cpu] Enable automatic CPU re-arm? [y/N]: ' >/dev/tty
  IFS= read -r answer </dev/tty || answer=n
  case "${answer,,}" in y|yes|s|si|sí) ;; *) die "cancelled" ;; esac

  install_rearm_manager_copy
  write_rearm_unit
  write_steamos_rearm_keep
  systemctl daemon-reload
  systemctl enable "$REARM_SERVICE" >/dev/null
  # Start once now to validate the unit. On an already-unlocked 16-thread session
  # the upstream manager is a no-op; on 12 threads it only arms the next warm boot.
  if ! systemctl start "$REARM_SERVICE"; then
    systemctl disable "$REARM_SERVICE" >/dev/null 2>&1 || true
    die "CPU re-arm service failed during validation; inspect: journalctl -u $REARM_SERVICE -b"
  fi
  say "CPU re-arm ENABLED"
  say "After a future cold boot: Linux starts at 6c/12t, this service re-arms 0xFF, then YOU warm reboot when you want 8c/16t."
  say "Disable anytime: sudo ./bc250-unlock cpu rearm disable"
}

rearm_disable_cmd() {
  need_root; prepare; need_cmd systemctl
  systemctl disable --now "$REARM_SERVICE" >/dev/null 2>&1 || true
  rm -f "$REARM_UNIT" "$REARM_KEEP_FILE"
  rm -f "$REARM_MANAGER"
  # Remove an empty private libexec directory on normal Linux; keep shared /opt paths intact.
  [ "$PLATFORM" = steamos ] || rmdir /usr/local/libexec/bc250-cu-unlock-suite 2>/dev/null || true
  systemctl daemon-reload
  systemctl reset-failed "$REARM_SERVICE" >/dev/null 2>&1 || true
  say "CPU re-arm disabled"
  say "Disabling re-arm does not clear an already-active or already-armed CPU mask; a full cold power cycle returns CPU enumeration to stock 6c/12t."
}

rearm_cmd() {
  case "${1:-status}" in
    status) rearm_status_cmd ;;
    enable|install|on) rearm_enable_cmd ;;
    disable|remove|uninstall|off) rearm_disable_cmd ;;
    *) usage >&2; die "unknown CPU re-arm command: ${1:-}" ;;
  esac
}

case "${1:-}" in
  status) status_cmd ;;
  unlock) unlock_cmd ;;
  quick) health_cmd quick ;;
  deep) health_cmd deep ;;
  rearm|re-arm|persist) shift || true; rearm_cmd "${1:-status}" ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; die "unknown command: $1" ;;
esac
