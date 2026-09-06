#!/usr/bin/env bash
# Shared helpers for BC-250 CU Unlock Suite frontends.
set -Eeuo pipefail

BC250_ROOT="${BC250_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=bc250-platform.sh
source "$BC250_ROOT/scripts/bc250-platform.sh"
BC250_PLATFORM_DETECTED="$(bc250_detect_platform)"

if [ -n "${BC250_STATE_DIR:-}" ]; then
  STATE_DIR="$BC250_STATE_DIR"
elif [ "$BC250_PLATFORM_DETECTED" = steamos ]; then
  STATE_DIR="$(bc250_steamos_state_dir)"
else
  STATE_DIR="/var/lib/bc250-probe"
fi

STEAMOS_PERSIST_ROOT="${BC250_STEAMOS_PERSIST_ROOT:-/opt/bc250-wgp-lab}"
STEAMOS_UMR="$STEAMOS_PERSIST_ROOT/umr/bin/umr"
STEAMOS_UMR_DB="$STEAMOS_PERSIST_ROOT/umr/share/umr/database"
STEAMOS_UMR_DB_TAR="$STEAMOS_PERSIST_ROOT/umr/share/umr/database.tar.zst"
STEAMOS_KEEP_FILE="/etc/atomic-update.conf.d/bc250-wgp-lab.conf"

# If SteamOS persistence created a UMR snapshot, prefer it for interactive
# operations as well as the boot-table EnvironmentFile written upstream.
if [ "$BC250_PLATFORM_DETECTED" = steamos ] && [ -x "$STEAMOS_UMR" ]; then
  export UMR="${UMR:-$STEAMOS_UMR}"
  if [ -d "$STEAMOS_UMR_DB" ]; then export UMR_DATABASE_PATH="${UMR_DATABASE_PATH:-$STEAMOS_UMR_DB}"; fi
fi

MANAGER="${BC250_MANAGER:-$BC250_ROOT/upstream/bc250-cu-live-manager/bc250-cu-live-manager.sh}"
VERIFY="${BC250_VERIFY:-$BC250_ROOT/upstream/bc250-40cu-unlock/scripts/bc250-compute-verify.sh}"
GPU_PROBE="$BC250_ROOT/scripts/bc250-gpu-probe.sh"
RESULTS="$STATE_DIR/gpu-results.tsv"
VISUAL_RESULTS="$STATE_DIR/gpu-visual-results.tsv"
DENYLIST="$STATE_DIR/gpu-manual-bad.tsv"
TOPOLOGY="$STATE_DIR/gpu-boot-wgp-map.tsv"
PROFILE_AUDIT="$STATE_DIR/persistence-profile.tsv"
UPSTREAM_SERVICE="bc250-cu-live-manager.service"
MAX_TEMP_C="${BC250_MAX_TEMP_C:-95}"

lab_say(){ printf '[bc250-unlock] %s\n' "$*"; }
lab_warn(){ printf '[bc250-unlock] WARNING: %s\n' "$*" >&2; }
lab_die(){ printf '[bc250-unlock] ERROR: %s\n' "$*" >&2; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || lab_die "run this command with sudo"; }
need_file(){ [ -f "$1" ] || lab_die "missing file: $1"; }
need_exec(){ [ -x "$1" ] || lab_die "missing executable: $1 (run ./setup.sh first)"; }
prepare_state(){
  mkdir -p "$STATE_DIR"
  if [ "$BC250_PLATFORM_DETECTED" = steamos ]; then chown root:root "$STATE_DIR" 2>/dev/null || true; fi
  touch "$RESULTS" "$VISUAL_RESULTS" "$DENYLIST"
  chmod 0700 "$STATE_DIR" 2>/dev/null || true
}
manager(){ "$MANAGER" --yes "$@"; }

latest_compute_status(){
  local w="$1"; awk -F'\t' -v w="$w" '$3==w{s=$4} END{print s}' "$RESULTS" 2>/dev/null || true
}
latest_visual_status(){
  local w="$1"; awk -F'\t' -v w="$w" '$3==w{s=$4} END{print s}' "$VISUAL_RESULTS" 2>/dev/null || true
}
is_denied(){
  local w="$1"; awk -F'\t' -v w="$w" '$1==w{f=1} END{exit !f}' "$DENYLIST" 2>/dev/null
}
load_candidates(){
  [ -r "$TOPOLOGY" ] || lab_die "no cached topology; run: sudo ./bc250-unlock doctor"
  mapfile -t FACTORY_WGPS < <(awk -F'\t' '$1=="factory"{print $2}' "$TOPOLOGY")
  mapfile -t CANDIDATE_WGPS < <(awk -F'\t' '$1=="candidate"{print $2}' "$TOPOLOGY")
  [ "${#FACTORY_WGPS[@]}" -eq 12 ] || lab_die "cached topology does not contain 12 factory WGPs"
  [ "${#CANDIDATE_WGPS[@]}" -eq 8 ] || lab_die "cached topology does not contain 8 candidates"
}
approved_wgps(){
  local w c v
  load_candidates
  for w in "${CANDIDATE_WGPS[@]}"; do
    is_denied "$w" && continue
    c="$(latest_compute_status "$w")"
    v="$(latest_visual_status "$w")"
    [ "$c" = PASS ] && [ "$v" = PASS_VISUAL ] && printf '%s\n' "$w"
  done
}
approved_count(){ mapfile -t _g < <(approved_wgps); printf '%s\n' "${#_g[@]}"; }
expected_cus(){ local n; n="$(approved_count)"; printf '%s\n' "$((24 + 2*n))"; }
latest_combined_status(){ awk -F'\t' '$3=="COMBINED"{s=$4} END{print s}' "$RESULTS" 2>/dev/null || true; }
latest_combined_detail(){ awk -F'\t' '$3=="COMBINED"{d=$5} END{print d}' "$RESULTS" 2>/dev/null || true; }

current_routed_cus(){
  need_exec "$MANAGER"
  "$MANAGER" status 2>/dev/null | sed -nE 's/.*CUs active[^:]*:[^0-9]*([0-9]+)\/40.*/\1/p' | tail -n1
}

max_amdgpu_temp_c(){
  local hw f raw max=""
  for hw in /sys/class/drm/card*/device/hwmon/hwmon*; do
    [ -r "$hw/name" ] || continue
    grep -q '^amdgpu$' "$hw/name" 2>/dev/null || continue
    for f in "$hw"/temp*_input; do
      [ -r "$f" ] || continue
      raw="$(cat "$f" 2>/dev/null || true)"; [[ "$raw" =~ ^[0-9]+$ ]] || continue
      raw=$((raw/1000)); if [ -z "$max" ] || [ "$raw" -gt "$max" ]; then max="$raw"; fi
    done
  done
  [ -n "$max" ] && printf '%s\n' "$max"
}

kernel_faults_since(){
  local since="$1"
  journalctl -k --since "@$since" --no-pager 2>/dev/null | \
    grep -Ei 'amdgpu.*(ring .*timeout|GPU reset|GPU fault|VM fault|VM_L2_PROTECTION_FAULT|RAS.*error|GPU recovery|amdgpu_job_timedout)|\[Hardware Error\]|Machine check|mce:' || true
}


steamos_conf_set(){
  local file="$1" key="$2" value="$3"
  [ -f "$file" ] || return 1
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

# Snapshot the exact UMR binary used for a validated SteamOS boot profile into
# /opt, which SteamOS offloads to persistent /home storage. If an extracted UMR
# database or package database archive is available, snapshot that too. The
# upstream service EnvironmentFile is then pointed at the persistent copy.
steamos_snapshot_umr(){
  [ "$BC250_PLATFORM_DETECTED" = steamos ] || return 0
  local conf="/etc/bc250-cu-live-manager.conf" src="${1:-}" db_src=""
  [ -f "$conf" ] || lab_die "SteamOS UMR snapshot requires $conf"
  if [ -z "$src" ]; then
    src="$(awk -F= '$1=="UMR"{sub(/^UMR=/,""); print; exit}' "$conf" 2>/dev/null || true)"
  fi
  [ -x "$src" ] || src="$(command -v umr 2>/dev/null || true)"
  [ -x "$src" ] || lab_die "cannot snapshot UMR for SteamOS persistence: executable not found"

  install -d -o root -g root -m 0755 "$(dirname -- "$STEAMOS_UMR")"
  if [ "$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")" != "$(readlink -f "$STEAMOS_UMR" 2>/dev/null || printf '%s' "$STEAMOS_UMR")" ]; then
    install -o root -g root -m 0755 "$src" "$STEAMOS_UMR"
  fi
  steamos_conf_set "$conf" UMR "$STEAMOS_UMR"

  db_src="$(awk -F= '$1=="UMR_DATABASE_PATH"{sub(/^UMR_DATABASE_PATH=/,""); print; exit}' "$conf" 2>/dev/null || true)"
  if [ -z "$db_src" ] || [ ! -d "$db_src" ]; then
    [ -d /var/lib/umr/database ] && db_src=/var/lib/umr/database
  fi
  if [ -n "$db_src" ] && [ -d "$db_src" ]; then
    install -d -o root -g root -m 0755 "$(dirname -- "$STEAMOS_UMR_DB")"
    if [ "$(readlink -f "$db_src" 2>/dev/null || printf '%s' "$db_src")" != "$(readlink -f "$STEAMOS_UMR_DB" 2>/dev/null || printf '%s' "$STEAMOS_UMR_DB")" ]; then
      rm -rf "$STEAMOS_UMR_DB"
      mkdir -p "$STEAMOS_UMR_DB"
      cp -a "$db_src"/. "$STEAMOS_UMR_DB"/
      chown -R root:root "$STEAMOS_UMR_DB"
      chmod -R go-w "$STEAMOS_UMR_DB"
    fi
    steamos_conf_set "$conf" UMR_DATABASE_PATH "$STEAMOS_UMR_DB"
    steamos_conf_set "$conf" UMR_DB_TAR ""
  elif [ -r /usr/share/umr/database/database.tar.zst ]; then
    install -D -o root -g root -m 0644 /usr/share/umr/database/database.tar.zst "$STEAMOS_UMR_DB_TAR"
    steamos_conf_set "$conf" UMR_DATABASE_PATH ""
    steamos_conf_set "$conf" UMR_DB_TAR "$STEAMOS_UMR_DB_TAR"
  else
    # The current UMR may work without an external DB. Keep the binary snapshot
    # and let post-update verification prove it before relying on persistence.
    steamos_conf_set "$conf" UMR_DATABASE_PATH ""
    steamos_conf_set "$conf" UMR_DB_TAR ""
  fi
  chmod 0644 "$conf"
}
