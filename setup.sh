#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/bc250-platform.sh"

usage(){ cat <<'USAGE'
Usage:
  ./setup.sh                         Interactive platform selection / auto-detect
  ./setup.sh --os auto              Auto-detect platform
  ./setup.sh --os cachyos           CachyOS / Arch path
  ./setup.sh --os steamos           Real SteamOS path (experimental)
  ./setup.sh --reuse /path/to/previous-tool-folder  Reuse already-tested upstream repos

SteamOS support is deliberately marked experimental until validated on more BC-250 boards.
USAGE
}

if [ "${1:-}" = "--reuse" ]; then
  src="${2:-}"
  [ -n "$src" ] || { echo "Usage: ./setup.sh --reuse /path/to/previous-tool-folder" >&2; exit 1; }
  [ -x "$src/upstream/bc250-cu-live-manager/bc250-cu-live-manager.sh" ] || { echo "No live-manager found under $src/upstream" >&2; exit 1; }
  [ -x "$src/upstream/bc250-40cu-unlock/scripts/bc250-compute-verify.sh" ] || { echo "No compute verifier found under $src/upstream" >&2; exit 1; }
  rm -rf "$ROOT/upstream"
  cp -a "$src/upstream" "$ROOT/upstream"
  echo "Reused tested upstream tree from: $src/upstream"
  printf 'live-manager commit: '; git -C "$ROOT/upstream/bc250-cu-live-manager" rev-parse HEAD 2>/dev/null || echo unknown
  printf '40cu repo commit   : '; git -C "$ROOT/upstream/bc250-40cu-unlock" rev-parse HEAD 2>/dev/null || echo unknown
  echo "Next: sudo ./bc250-unlock status"
  exit 0
fi

os=""
if [ "${1:-}" = "--os" ]; then os="${2:-}"; shift 2 || true
elif [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then usage; exit 0
elif [ $# -gt 0 ]; then echo "Unknown setup argument: $1" >&2; usage >&2; exit 1
fi

if [ -z "$os" ]; then
  detected="$(bc250_detect_platform)"
  if [ -t 0 ]; then
    echo "BC-250 CU Unlock Suite setup"
    echo "Detected platform: $(bc250_platform_label)"
    echo
    echo "  1) Auto-detect (recommended: $detected)"
    echo "  2) CachyOS / Arch Linux"
    echo "  3) SteamOS (real/Valve-style atomic image) [EXPERIMENTAL]"
    printf 'Choose [1-3]: '
    read -r choice
    case "$choice" in 2) os=cachyos ;; 3) os=steamos ;; *) os=auto ;; esac
  else os=auto; fi
fi

case "$os" in
  auto) os="$(bc250_detect_platform)" ;;
  arch) os=cachyos ;;
  steam|steamos-real) os=steamos ;;
esac

case "$os" in
  cachyos) exec bash "$ROOT/scripts/bootstrap-cachyos.sh" "$@" ;;
  steamos) exec bash "$ROOT/scripts/bootstrap-steamos.sh" "$@" ;;
  *) echo "Could not select a supported platform (detected: $os). Use --os cachyos or --os steamos." >&2; exit 1 ;;
esac
