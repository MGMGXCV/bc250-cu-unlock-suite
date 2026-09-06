#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bc250-common.sh"
ROOT="$BC250_ROOT"
BOOTSTRAP="$SCRIPT_DIR/bootstrap-steamos.sh"

usage(){ cat <<'USAGE'
Usage:
  sudo ./bc250-unlock steamos verify
  sudo ./bc250-unlock steamos repair
  sudo ./bc250-unlock steamos keep-status

verify      Read-only health check after a SteamOS update.
repair      Reinstall/check host dependencies + UMR, then repair boot service if configured.
keep-status Show atomic-update keep-list coverage for the CU boot profile.
USAGE
}

need_steamos(){ [ "$BC250_PLATFORM_DETECTED" = steamos ] || lab_die "SteamOS not detected"; }

verify_cmd(){
  need_root; need_steamos
  local bad=0 c service_exec=""
  printf 'Platform            : %s\n' "$(bc250_platform_label)"
  printf 'SteamOS version     : '; (. /etc/os-release; printf '%s\n' "${VERSION_ID:-unknown}")
  printf 'Kernel              : %s\n' "$(uname -r)"
  printf 'State directory     : %s\n' "$STATE_DIR"
  printf 'Read-only status    : %s\n' "$(steamos-readonly status 2>&1 || echo unknown)"
  for c in git gcc glslangValidator python3 lspci stress-ng umr; do
    if command -v "$c" >/dev/null 2>&1; then printf '%-20s: OK (%s)\n' "$c" "$(command -v "$c")"
    else printf '%-20s: MISSING\n' "$c"; bad=1; fi
  done
  if [ -r /usr/include/vulkan/vulkan.h ]; then echo 'Vulkan headers      : OK'; else echo 'Vulkan headers      : MISSING'; bad=1; fi
  if ldconfig -p 2>/dev/null | grep -q 'libvulkan\.so'; then echo 'Vulkan loader       : OK'; else echo 'Vulkan loader       : MISSING'; bad=1; fi
  if [ -x "$MANAGER" ]; then echo 'live-manager        : OK'; else echo 'live-manager        : MISSING (run setup)'; bad=1; fi
  if [ -x "$VERIFY" ]; then echo 'compute verifier    : OK'; else echo 'compute verifier    : MISSING (run setup)'; bad=1; fi
  if systemctl is-enabled --quiet "$UPSTREAM_SERVICE" 2>/dev/null; then
    echo 'CU boot service     : ENABLED'
    service_exec="$(systemctl cat "$UPSTREAM_SERVICE" 2>/dev/null | sed -n 's/^ExecStart=//p' | tail -n1)"
    printf 'Service ExecStart   : %s\n' "${service_exec:-unknown}"
    case "$service_exec" in
      /opt/bc250-wgp-lab/bin/bc250-cu-live-manager*) echo 'Pinned manager      : OK' ;;
      *) echo 'Pinned manager      : WRONG/MISSING'; bad=1 ;;
    esac
    [ -f /etc/bc250-cu-live-manager.conf ] || { echo 'Saved CU table      : MISSING'; bad=1; }
    if grep -q '^UMR=/opt/bc250-wgp-lab/umr/bin/umr$' /etc/bc250-cu-live-manager.conf 2>/dev/null && [ -x "$STEAMOS_UMR" ]; then
      echo 'Persistent UMR      : OK'
    else
      echo 'Persistent UMR      : MISSING/not pinned'; bad=1
    fi
    if [ -x /opt/bc250-wgp-lab/bin/bc250-cu-live-manager ] && [ -f /etc/bc250-cu-live-manager.conf ]; then
      if /opt/bc250-wgp-lab/bin/bc250-cu-live-manager --yes --dry-run apply-service >/dev/null 2>&1; then
        echo 'Boot profile dry-run: OK'
      else
        echo 'Boot profile dry-run: FAIL'; bad=1
      fi
    fi
    if [ -f "$STEAMOS_KEEP_FILE" ]; then
      echo "Atomic keep list    : $STEAMOS_KEEP_FILE"
    else
      echo 'Atomic keep list    : MISSING'; bad=1
    fi
  else
    echo 'CU boot service     : disabled/not installed'
    if [ -f "$STEAMOS_KEEP_FILE" ]; then
      echo "Atomic keep list    : $STEAMOS_KEEP_FILE (stale?)"
    else
      echo 'Atomic keep list    : absent (normal until persist install)'
    fi
  fi
  if [ "$bad" -eq 0 ]; then lab_say 'SteamOS health check PASS'; else lab_warn 'SteamOS health check found missing pieces; run: sudo ./bc250-unlock steamos repair'; return 1; fi
}

repair_cmd(){
  need_root; need_steamos
  # bootstrap wants to be launched from the normal user because it uses sudo internally.
  local user="${SUDO_USER:-}" home=""
  [ -n "$user" ] && [ "$user" != root ] || lab_die "run this from your normal Desktop user as: sudo ./bc250-unlock steamos repair"
  lab_say "repairing SteamOS host dependencies using setup bootstrap"
  sudo -u "$user" bash "$BOOTSTRAP"
  if [ -s /etc/bc250-cu-live-manager.conf ]; then
    lab_say 'a saved CU table exists; repairing/re-enabling upstream boot service without changing the table'
    if [ -x /usr/bin/umr ]; then UMR=/usr/bin/umr "$MANAGER" --yes install-service; else "$MANAGER" --yes install-service; fi
    steamos_snapshot_umr /usr/bin/umr
    install -D -o root -g root -m 0755 "$MANAGER" /opt/bc250-wgp-lab/bin/bc250-cu-live-manager
    if [ -f /etc/systemd/system/$UPSTREAM_SERVICE ]; then
      sed -i 's|^ExecStart=.*|ExecStart=/opt/bc250-wgp-lab/bin/bc250-cu-live-manager --yes apply-service|' /etc/systemd/system/$UPSTREAM_SERVICE
    fi
    systemctl daemon-reload
    systemctl enable "$UPSTREAM_SERVICE" >/dev/null
    # Recreate the atomic-update keep list without changing the saved CU table.
    install -d -m 0755 /etc/atomic-update.conf.d
    cat > "$STEAMOS_KEEP_FILE" <<EOF_KEEP
# BC-250 CU Unlock Suite CU persistence retained across SteamOS atomic updates.
/etc/bc250-cu-live-manager.conf
/etc/systemd/system/bc250-cu-live-manager.service
/etc/systemd/system/multi-user.target.wants/bc250-cu-live-manager.service
$STEAMOS_KEEP_FILE
EOF_KEEP
    chmod 0644 "$STEAMOS_KEEP_FILE"
  fi
  lab_say 'repair complete; run: sudo ./bc250-unlock steamos verify'
}

keep_status(){
  need_root; need_steamos
  if [ -f "$STEAMOS_KEEP_FILE" ]; then
    printf 'Atomic-update keep list: %s\n' "$STEAMOS_KEEP_FILE"
    cat "$STEAMOS_KEEP_FILE"
    if [ -x /usr/lib/holo/holo-sync-var ]; then
      echo
      echo 'holo-sync-var dry-run (informational):'
      /usr/lib/holo/holo-sync-var --dry-run all 2>&1 | grep -E 'bc250|cu-live' || true
    fi
  else
    echo 'No BC-250 CU Unlock Suite atomic-update keep list is installed.'
  fi
}

case "${1:-}" in
  verify|status) verify_cmd ;;
  repair) repair_cmd ;;
  keep-status|keep) keep_status ;;
  help|-h|--help|"") usage ;;
  *) usage >&2; lab_die "unknown SteamOS command: $1" ;;
esac
