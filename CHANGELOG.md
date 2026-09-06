# Changelog

## 0.4.0 — BC-250 CU Unlock Suite rebrand

- Renamed the public project from **BC-250 WGP Lab** to **BC-250 CU Unlock Suite**.
- New canonical executable: `./bc250-unlock`.
- Retained `./bc250-lab` as a backward-compatible forwarding alias.
- Renamed GUI, CLI headers, desktop launcher, reports, documentation and GitHub templates to the new public identity.
- Added the public tagline: **Discover. Test. Unlock. / Descubre. Prueba. Desbloquea.**
- Kept legacy SteamOS persistent directory names internally so existing 0.2/0.3 installs do not lose state or boot persistence.
- Carried forward the v0.3.3 light-theme readability improvements.
- No change to WGP routing, compute validation, visual validation or persistence safety gates.

## 0.3.3 — GUI light-theme readability polish

- Fixed remaining low-contrast cards in light themes, especially the status, step-by-step and tools sections.
- Light mode now uses light card backgrounds with dark text for status cards, tool cards, step cards and platform blocks.
- Improved hover/outline styling for maintenance and danger actions in light themes.
- No GPU-routing or persistence logic changes. This is a presentation/accessibility-only release.

## 0.3.2 — GUI contrast, attribution and release/legal docs

- Fixed protected-mode readability in light themes: the page no longer dims whole sections; disabled controls are styled separately and text keeps high contrast.
- Increased light/dark muted-text contrast and disabled-button contrast.
- Added bilingual GUI footer safety/AI-assistance disclosure.
- Added `SAFETY.md`, `ACKNOWLEDGEMENTS.md`, `docs/REFERENCES.md` and `docs/LICENSING.md`.
- Clarified MIT as the recommended license for BC-250 CU Unlock Suite-authored code.
- Clarified third-party license boundaries: duggasco GPL-2.0; live-manager fetched separately and not vendored/relicensed.
- Updated GitHub publishing guidance and release checklist.


## 0.3.1

- GUI now detects active boot persistence and enters a protected/configured mode.
- Diagnostic actions that intentionally conflict with persistence (wizard, doctor, baseline, scans, apply, soak, stock/recover) are disabled in the GUI while the boot-restore service is enabled.
- The localhost backend enforces the same lock, so bypassing the disabled buttons cannot launch conflicting tests.
- Added a bilingual persistent-profile banner explaining why diagnostic controls are unavailable.
- Status, results, reports, persistence status/removal, and SteamOS maintenance remain available.
- Fixes the confusing beginner experience where clicking Baseline with an already-persistent profile opened a terminal that immediately failed by design.

## 0.3.0

- Added optional bilingual Spanish/English graphical guide (`./bc250-unlock gui`).
- GUI runs localhost-only and launches the canonical CLI in a visible terminal.
- Added fixed action whitelist, per-session token and no arbitrary shell-command endpoint.
- Added beginner step-by-step workflow plus status/recovery/persistence tools.
- Added SteamOS-specific Verify/Repair section in graphical mode.
- Added optional per-user application-menu shortcut (`gui-shortcut install/remove`).
- Added `docs/GUI.md`, `README_ES.md` and GUI self-test/CI syntax validation.
- Kept all GPU routing, validation and persistence logic in the existing CLI.
- Made `results` explicitly root-read because the runtime state directory is intentionally private (`0700`).

## 0.2.0 - 2026-09-05

- Added an explicit SteamOS platform path (`./setup.sh --os steamos`).
- Added interactive Auto/CachyOS/SteamOS setup selection.
- Added platform-aware persistent state storage on SteamOS under the shared
  `/home/.steamos/offload` tree.
- Added `bc250-unlock platform`.
- Added `bc250-unlock steamos verify`, `repair`, and `keep-status`.
- SteamOS persistence snapshots UMR + the live-manager helper under persistent
  `/opt`, rewrites the saved table to use that UMR, and adds an atomic-update
  keep list for the CU config/unit.
- Added SteamOS documentation and post-update safety guidance.
- SteamOS support remains explicitly experimental pending additional hardware
  validation; CachyOS/Arch remains the validated path.

## 0.1.0 — 2026-09-05

Initial public-ready experimental release.

- Board-local irregular harvest-map discovery.
- Per-WGP Vulkan compute correctness testing.
- Crash/reboot attribution with pending markers.
- Real-desktop human visual gate after compute PASS.
- Persistent manual denylist for visual-bad WGPs.
- Combined compute + visual validation.
- Long combined soak test.
- Markdown report generator.
- Persistence wrapper using upstream live-manager saved-table/systemd support.
- Safe rollback to factory live routing.
- Optional offscreen graphics and CPU research helpers.
