#!/usr/bin/env bash
# Fetch only the upstream tools used by the wrappers and install CachyOS/Arch dependencies.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UP="$SCRIPT_DIR/../upstream"

command -v pacman >/dev/null 2>&1 || { echo "This bootstrap is for CachyOS/Arch (pacman)." >&2; exit 1; }
command -v sudo >/dev/null 2>&1 || { echo "sudo is required" >&2; exit 1; }

echo "Installing build/Vulkan/test dependencies..."
sudo pacman -S --needed --noconfirm git base-devel python pciutils libdrm glslang vulkan-headers vulkan-icd-loader vulkan-radeon stress-ng mesa libglvnd

mkdir -p "$UP"
clone_or_update() {
  local url="$1" dir="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only
  else
    git clone --depth=1 "$url" "$dir"
  fi
}

clone_or_update https://github.com/WinnieLV/bc250-cu-live-manager.git "$UP/bc250-cu-live-manager"
clone_or_update https://github.com/duggasco/bc250-40cu-unlock.git "$UP/bc250-40cu-unlock"
chmod +x "$UP/bc250-cu-live-manager/bc250-cu-live-manager.sh" \
         "$UP/bc250-40cu-unlock/scripts/bc250-compute-verify.sh"

if ! command -v umr >/dev/null 2>&1; then
  echo "Installing UMR using the live-manager's Arch/CachyOS-aware installer..."
  sudo "$UP/bc250-cu-live-manager/bc250-cu-live-manager.sh" install-umr
fi

echo
printf 'live-manager commit: '; git -C "$UP/bc250-cu-live-manager" rev-parse HEAD
printf '40cu repo commit   : '; git -C "$UP/bc250-40cu-unlock" rev-parse HEAD

echo
echo "Bootstrap complete. Next:"
echo "  sudo $SCRIPT_DIR/../bc250-unlock doctor"
echo "  sudo $SCRIPT_DIR/../bc250-unlock wizard"
echo "  Optional GUI: $SCRIPT_DIR/../bc250-unlock gui"
