#!/usr/bin/env bash
# SteamOS bootstrap. Installs only the host tools needed for WGP discovery/tests,
# then restores SteamOS read-only mode. Host packages may need repair after an OS update.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
UP="$ROOT/upstream"
# shellcheck source=bc250-platform.sh
source "$SCRIPT_DIR/bc250-platform.sh"

say(){ printf '[bc250-steamos-setup] %s\n' "$*"; }
die(){ printf '[bc250-steamos-setup] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(bc250_detect_platform)" = steamos ] || die "SteamOS was not detected. Use ./setup.sh --os cachyos on CachyOS/Arch."
command -v steamos-readonly >/dev/null 2>&1 || die "steamos-readonly not found; this path targets real/Valve-style SteamOS"
command -v sudo >/dev/null 2>&1 || die "sudo is required"
command -v pacman >/dev/null 2>&1 || die "pacman not found; unsupported SteamOS image"

readonly_changed=0
restore_readonly(){
  local rc=$?
  trap - EXIT INT TERM HUP
  if [ "$readonly_changed" -eq 1 ]; then
    say "re-enabling SteamOS read-only mode"
    sudo steamos-readonly enable >/dev/null 2>&1 || printf '[bc250-steamos-setup] WARNING: failed to re-enable read-only mode\n' >&2
  fi
  exit "$rc"
}
trap restore_readonly EXIT INT TERM HUP

make_writable(){
  local st
  st="$(steamos-readonly status 2>&1 || true)"
  if printf '%s\n' "$st" | grep -qi enabled; then
    say "temporarily disabling SteamOS read-only mode"
    sudo steamos-readonly disable
    readonly_changed=1
  elif printf '%s\n' "$st" | grep -qi disabled; then
    say "SteamOS read-only mode is already disabled; leaving it in that state"
  else
    say "read-only state was not recognized; attempting a temporary disable"
    sudo steamos-readonly disable
    readonly_changed=1
  fi
}

# Packages required by our Vulkan verifier plus ordinary diagnostics. SteamOS
# already ships many of these; pacman --needed only adds what is absent.
HOST_PKGS=(git base-devel gcc python pciutils libdrm glslang vulkan-headers vulkan-icd-loader vulkan-radeon stress-ng mesa libglvnd zstd)

say "SteamOS uses an atomic/read-only system image. Packages added under /usr can disappear after an OS update."
say "The lab stores results in /home/.steamos/offload and provides: sudo ./bc250-unlock steamos repair"
make_writable
say "installing/checking host test dependencies"
if ! sudo pacman -S --needed --noconfirm "${HOST_PKGS[@]}"; then
  die "pacman dependency install failed. Do not use pacman -Syu to repair SteamOS; update SteamOS normally, then retry."
fi

mkdir -p "$UP"
clone_or_update(){
  local url="$1" dir="$2"
  if [ -d "$dir/.git" ]; then git -C "$dir" pull --ff-only
  else git clone --depth=1 "$url" "$dir"
  fi
}
clone_or_update https://github.com/WinnieLV/bc250-cu-live-manager.git "$UP/bc250-cu-live-manager"
clone_or_update https://github.com/duggasco/bc250-40cu-unlock.git "$UP/bc250-40cu-unlock"
chmod +x "$UP/bc250-cu-live-manager/bc250-cu-live-manager.sh" \
         "$UP/bc250-40cu-unlock/scripts/bc250-compute-verify.sh"

# Return the image to read-only before asking upstream to install UMR. Current
# live-manager knows how to toggle SteamOS read-only mode around its own install.
if [ "$readonly_changed" -eq 1 ]; then
  say "re-enabling read-only mode before UMR setup"
  sudo steamos-readonly enable
  readonly_changed=0
fi

if ! command -v umr >/dev/null 2>&1; then
  say "installing UMR with the upstream live-manager's SteamOS-aware installer"
  sudo "$UP/bc250-cu-live-manager/bc250-cu-live-manager.sh" --yes install-umr || \
    die "UMR installation failed. SteamOS repositories/images vary; see docs/STEAMOS.md and retry after a normal SteamOS update."
fi

# Persistent root-owned state lives on SteamOS's shared /home offload tree.
sudo install -d -o root -g root -m 0700 /home/.steamos/offload/var/lib/bc250-wgp-lab

# Sanity-check the exact tools the compute verifier needs.
missing=0
for c in git gcc glslangValidator python3 lspci stress-ng umr; do
  if ! command -v "$c" >/dev/null 2>&1; then printf '[bc250-steamos-setup] MISSING: %s\n' "$c" >&2; missing=1; fi
done
[ -r /usr/include/vulkan/vulkan.h ] || { printf '[bc250-steamos-setup] MISSING: /usr/include/vulkan/vulkan.h\n' >&2; missing=1; }
ldconfig -p 2>/dev/null | grep -q 'libvulkan\.so' || { printf '[bc250-steamos-setup] MISSING: libvulkan.so\n' >&2; missing=1; }
[ "$missing" -eq 0 ] || die "one or more verifier dependencies are still missing"

echo
printf 'live-manager commit: '; git -C "$UP/bc250-cu-live-manager" rev-parse HEAD
printf '40cu repo commit   : '; git -C "$UP/bc250-40cu-unlock" rev-parse HEAD
printf 'SteamOS version    : '; (. /etc/os-release; printf '%s\n' "${VERSION_ID:-unknown}")
printf 'Kernel             : %s\n' "$(uname -r)"
echo
say "Bootstrap complete. This SteamOS path is EXPERIMENTAL until validated on more BC-250 boards."
say "Next: sudo $ROOT/bc250-unlock doctor"
say "Then: sudo $ROOT/bc250-unlock wizard"
say "Optional GUI (without sudo): $ROOT/bc250-unlock gui"
say "After any SteamOS update: sudo $ROOT/bc250-unlock steamos verify"
