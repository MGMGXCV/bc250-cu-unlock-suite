#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_FILE="$APP_DIR/bc250-cu-unlock-suite.desktop"
LEGACY_DESKTOP_FILE="$APP_DIR/bc250-wgp-lab.desktop"

usage(){ cat <<'EOF'
Usage:
  ./bc250-unlock gui-shortcut install
  ./bc250-unlock gui-shortcut remove
  ./bc250-unlock gui-shortcut status

Installs a per-user desktop/menu launcher for the optional graphical guide.
Do not run this command with sudo.
EOF
}

need_user(){ [ "${EUID:-$(id -u)}" -ne 0 ] || { echo '[bc250-gui] ERROR: install/remove the desktop shortcut without sudo.' >&2; exit 2; }; }

install_shortcut(){
  need_user
  mkdir -p "$APP_DIR"
  rm -f "$LEGACY_DESKTOP_FILE"
  # Desktop Exec quoting is not shell quoting. Escape backslash and double quote.
  local exec_path="$ROOT/bc250-unlock"
  exec_path="${exec_path//\\/\\\\}"
  exec_path="${exec_path//\"/\\\"}"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=BC-250 CU Unlock Suite
Name[es]=BC-250 CU Unlock Suite
Comment=Beginner-friendly graphical guide for BC-250 CU/WGP testing and selective unlocking
Comment[es]=Guía gráfica para probar CUs/WGPs y desbloquear de forma selectiva la BC-250
Exec="$exec_path" gui
Icon=utilities-system-monitor
Terminal=false
Categories=System;Utility;
Keywords=BC-250;AMD;GPU;WGP;CU;
StartupNotify=true
EOF
  chmod 0644 "$DESKTOP_FILE"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  echo "[bc250-gui] Desktop shortcut installed: $DESKTOP_FILE"
  echo "[bc250-gui] It should appear in your application menu as 'BC-250 CU Unlock Suite'."
}

remove_shortcut(){
  need_user
  rm -f "$DESKTOP_FILE" "$LEGACY_DESKTOP_FILE"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  echo "[bc250-gui] Desktop shortcut removed: $DESKTOP_FILE"
}

case "${1:-status}" in
  install) install_shortcut ;;
  remove|uninstall) remove_shortcut ;;
  status) if [ -f "$DESKTOP_FILE" ]; then echo "installed: $DESKTOP_FILE"; else echo "not installed"; fi ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
