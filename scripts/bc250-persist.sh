#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bc250-common.sh
source "$SCRIPT_DIR/bc250-common.sh"


STEAMOS_MANAGER_BIN="${BC250_STEAMOS_MANAGER_BIN:-/opt/bc250-wgp-lab/bin/bc250-cu-live-manager}"

steamos_write_keep_list(){
  [ "$BC250_PLATFORM_DETECTED" = steamos ] || return 0
  install -d -o root -g root -m 0755 /etc/atomic-update.conf.d
  cat > "$STEAMOS_KEEP_FILE" <<EOF_KEEP
# BC-250 CU Unlock Suite CU persistence retained across SteamOS atomic updates.
/etc/bc250-cu-live-manager.conf
/etc/systemd/system/bc250-cu-live-manager.service
/etc/systemd/system/multi-user.target.wants/bc250-cu-live-manager.service
$STEAMOS_KEEP_FILE
EOF_KEEP
  chmod 0644 "$STEAMOS_KEEP_FILE"
}

steamos_pin_manager_service(){
  [ "$BC250_PLATFORM_DETECTED" = steamos ] || return 0
  install -D -o root -g root -m 0755 "$MANAGER" "$STEAMOS_MANAGER_BIN"
  [ -f /etc/systemd/system/$UPSTREAM_SERVICE ] || lab_die "upstream service file is missing after install-service"
  sed -i "s|^ExecStart=.*|ExecStart=$STEAMOS_MANAGER_BIN --yes apply-service|" "/etc/systemd/system/$UPSTREAM_SERVICE"
  systemctl daemon-reload
  systemctl enable "$UPSTREAM_SERVICE" >/dev/null
  steamos_write_keep_list
  lab_say "SteamOS: manager helper pinned under /opt and atomic-update keep list installed"
}

steamos_remove_persistence_helpers(){
  [ "$BC250_PLATFORM_DETECTED" = steamos ] || return 0
  rm -f "$STEAMOS_KEEP_FILE" "$STEAMOS_MANAGER_BIN"
  rm -rf "$STEAMOS_PERSIST_ROOT/umr"
  rmdir /opt/bc250-wgp-lab/bin /opt/bc250-wgp-lab 2>/dev/null || true
}

usage(){ cat <<'USAGE'
Usage:
  sudo ./bc250-unlock persist status
  sudo ./bc250-unlock persist install
  sudo ./bc250-unlock persist remove
  sudo ./bc250-unlock persist reapply

Persistence uses bc250-cu-live-manager's own saved table + systemd service.
It never writes BIOS/firmware and refuses to install unless the latest combined
validation is PASS for the same approved CU count.
USAGE
}

verify_combined_gate(){
  local st detail expected
  st="$(latest_combined_status)"; detail="$(latest_combined_detail)"; expected="$(expected_cus)"
  [ "$st" = PASS ] || lab_die "latest COMBINED result is '${st:-NONE}', not PASS; run: sudo ./bc250-unlock apply"
  [[ "$detail" == "$expected"CU* ]] || lab_die "latest combined PASS does not match current approved set (${expected} CU); rerun: sudo ./bc250-unlock apply"
}

save_audit_profile(){
  local expected manager_commit verify_commit now live
  expected="$(expected_cus)"; now="$(date -Iseconds)"; live="$(current_routed_cus || true)"
  manager_commit="$(git -C "$BC250_ROOT/upstream/bc250-cu-live-manager" rev-parse HEAD 2>/dev/null || echo unknown)"
  verify_commit="$(git -C "$BC250_ROOT/upstream/bc250-40cu-unlock" rev-parse HEAD 2>/dev/null || echo unknown)"
  {
    printf '# BC-250 CU Unlock Suite persistence audit profile\n'
    printf 'saved_at\t%s\n' "$now"
    printf 'expected_cus\t%s\n' "$expected"
    printf 'live_cus_at_save\t%s\n' "${live:-unknown}"
    printf 'kernel\t%s\n' "$(uname -r)"
    printf 'manager_commit\t%s\n' "$manager_commit"
    printf 'verifier_commit\t%s\n' "$verify_commit"
    while read -r w; do printf 'approved_wgp\t%s\n' "$w"; done < <(approved_wgps)
    while IFS=$'\t' read -r kind w; do [ "$kind" = factory ] && printf 'factory_wgp\t%s\n' "$w"; done < "$TOPOLOGY"
  } > "$PROFILE_AUDIT"
  chmod 0600 "$PROFILE_AUDIT" 2>/dev/null || true
}

status_cmd(){
  need_root; prepare_state; need_exec "$MANAGER"
  local expected live
  expected="$(expected_cus 2>/dev/null || echo '?')"; live="$(current_routed_cus || true)"
  printf 'Persistence service : '
  if systemctl is-enabled --quiet "$UPSTREAM_SERVICE" 2>/dev/null; then printf 'ENABLED\n'; else printf 'disabled/not installed\n'; fi
  printf 'Current routed CUs  : %s/40\n' "${live:-unknown}"
  printf 'Approved target CUs : %s/40\n' "$expected"
  [ -f /etc/bc250-cu-live-manager.conf ] && printf 'Saved boot table    : /etc/bc250-cu-live-manager.conf\n' || printf 'Saved boot table    : none\n'
  [ -f "$PROFILE_AUDIT" ] && { printf 'Lab audit profile   : %s\n' "$PROFILE_AUDIT"; sed -n '1,80p' "$PROFILE_AUDIT"; }
  if [ "$BC250_PLATFORM_DETECTED" = steamos ]; then
    printf 'SteamOS keep list   : '; [ -f "$STEAMOS_KEEP_FILE" ] && printf '%s\n' "$STEAMOS_KEEP_FILE" || printf 'missing\n'
    printf 'SteamOS manager bin : '; [ -x "$STEAMOS_MANAGER_BIN" ] && printf '%s\n' "$STEAMOS_MANAGER_BIN" || printf 'missing\n'
  fi
  return 0
}

install_cmd(){
  need_root; prepare_state; need_exec "$MANAGER"; need_exec "$GPU_PROBE"
  [ ! -e "$STATE_DIR/gpu-pending" ] || lab_die "pending crash marker exists; run: sudo ./bc250-unlock recover"
  if systemctl is-enabled --quiet "$UPSTREAM_SERVICE" 2>/dev/null; then
    lab_die "$UPSTREAM_SERVICE is already enabled; run persist status/remove before changing the saved profile"
  fi
  verify_combined_gate
  mapfile -t good < <(approved_wgps)
  [ "${#good[@]}" -gt 0 ] || lab_die "no approved WGPs"
  local expected live answer
  expected=$((24 + 2*${#good[@]}))
  lab_say "approved persistent target: ${good[*]} => ${expected}/40 CUs"
  printf '[bc250-unlock] This will save that exact LIVE routing and enable boot restore. Continue? [y/N]: ' >/dev/tty
  IFS= read -r answer </dev/tty || answer=n
  case "${answer,,}" in y|yes|s|si|sí) ;; *) lab_die "cancelled" ;; esac

  manager stock-dispatch >/dev/null
  manager enable-wgp "${good[@]}" >/dev/null
  live="$(current_routed_cus || true)"
  [ "$live" = "$expected" ] || { manager stock-dispatch >/dev/null 2>&1 || true; lab_die "live routing verification failed: expected $expected CUs, saw ${live:-unknown}"; }

  lab_say "saving current ${expected}-CU table using upstream manager"
  manager write-service-table
  [ "$BC250_PLATFORM_DETECTED" != steamos ] || steamos_snapshot_umr
  [ -s /etc/bc250-cu-live-manager.conf ] || { manager stock-dispatch >/dev/null 2>&1 || true; lab_die "upstream manager did not create /etc/bc250-cu-live-manager.conf"; }
  lab_say "installing upstream boot-restore service"
  manager install-service
  steamos_pin_manager_service
  systemctl is-enabled --quiet "$UPSTREAM_SERVICE" || lab_die "service install returned but $UPSTREAM_SERVICE is not enabled"
  save_audit_profile
  lab_say "persistence ENABLED for ${expected}/40 CUs"
  lab_say "rollback: sudo ./bc250-unlock persist remove"
  lab_say "after the next reboot: sudo ./bc250-unlock status"
}

remove_cmd(){
  need_root; prepare_state; need_exec "$MANAGER"
  lab_say "removing boot restore using upstream manager"
  manager uninstall-service || true
  lab_say "restoring factory boot-driver routing now"
  manager stock-dispatch
  rm -f "$PROFILE_AUDIT"
  steamos_remove_persistence_helpers
  lab_say "persistence removed; current live routing restored to stock 24 CUs"
}

reapply_cmd(){
  need_root; need_exec "$MANAGER"
  [ -s /etc/bc250-cu-live-manager.conf ] || lab_die "no saved upstream table"
  manager apply-service
  local live; live="$(current_routed_cus || true)"
  lab_say "saved table applied; current routed CUs=${live:-unknown}/40"
}

case "${1:-}" in
  status) status_cmd ;;
  install) install_cmd ;;
  remove|uninstall|rollback) remove_cmd ;;
  reapply) reapply_cmd ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; lab_die "unknown persist command: $1" ;;
esac
