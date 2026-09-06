#!/usr/bin/env bash
# Platform detection helpers. Source-safe: does not set shell options.

bc250_detect_platform() {
  if [ -n "${BC250_PLATFORM:-}" ]; then
    case "$BC250_PLATFORM" in
      steamos|cachyos) printf '%s\n' "$BC250_PLATFORM"; return 0 ;;
    esac
  fi
  if [ -f /etc/os-release ]; then
    local id="" name=""
    id="$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-}")"
    name="$(. /etc/os-release 2>/dev/null; printf '%s %s' "${NAME:-}" "${PRETTY_NAME:-}")"
    case "${id,,}" in steamos|holo) printf 'steamos\n'; return 0 ;; esac
    if printf '%s\n' "$name" | grep -Eqi 'SteamOS|Steam OS'; then printf 'steamos\n'; return 0; fi
    case "${id,,}" in cachyos|arch) printf 'cachyos\n'; return 0 ;; esac
  fi
  if command -v steamos-readonly >/dev/null 2>&1; then printf 'steamos\n'; return 0; fi
  if command -v pacman >/dev/null 2>&1; then printf 'cachyos\n'; return 0; fi
  printf 'unknown\n'
}

bc250_is_steamos() { [ "$(bc250_detect_platform)" = steamos ]; }
bc250_is_cachyos() { [ "$(bc250_detect_platform)" = cachyos ]; }

bc250_platform_label() {
  case "$(bc250_detect_platform)" in
    steamos) printf 'SteamOS (real/Valve-style atomic image)' ;;
    cachyos) printf 'CachyOS / Arch Linux' ;;
    *) printf 'Unknown Linux platform' ;;
  esac
}

bc250_steamos_state_dir() {
  printf '%s\n' "${BC250_STEAMOS_STATE_DIR:-/home/.steamos/offload/var/lib/bc250-wgp-lab}"
}
