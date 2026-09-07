# Release notes — v0.5.0

# BC-250 CU Unlock Suite

**Discover. Test. Unlock.**

Version 0.5.0 promotes the BC-250 CPU-core unlock into a documented first-class
workflow and adds an optional advanced **automatic CPU re-arm** mode while keeping
the GPU CU/WGP validation model unchanged.

## Highlights

- CPU unlock is now visible in the main CLI and bilingual GUI:
  `cpu status`, `cpu unlock`, `cpu quick`, and `cpu deep`.
- Added advanced `cpu rearm status|enable|disable` commands.
- Automatic CPU re-arm is **OFF by default**.
- Re-arm enable is blocked until one complete `cpu deep` run records PASS for
  physical cores 3 and 7 plus the all-thread stage from the same log.
- Re-arm never reboots the system automatically.
- After a cold boot, re-arm only saves the manual `cpu unlock` step: the current
  session remains 6c/12t until the user chooses a warm reboot to activate 8c/16t.
- Added a dedicated CPU section to the GUI, including a clearly labeled advanced
  re-arm switch and 6c/12t vs 8c/16t status.
- Added `docs/CPU.md` with validation, recovery and re-arm behavior.
- CPU actions remain available even when a validated GPU boot profile is active,
  preserving separation between GPU persistence and CPU testing.

## Hardware validation

The reference development board was exercised at 8c/16t with:

- quick PASS on physical cores 3 and 7 plus all threads;
- deep PASS on physical cores 3 and 7 plus all threads;
- real-game testing without observed CPU instability;
- cold power recovery back to 6c/12t;
- a subsequent successful re-unlock to 8c/16t.

The same board retains its separately validated 34/40-CU GPU profile. These are
board-specific results, not profiles or guarantees for other BC-250 units.

## CPU re-arm safety model

The optional re-arm service delegates the known volatile `0x77 -> 0xFF` SMU
operation to the separately fetched `bc250-cu-live-manager`. It does not vendor or
reimplement arbitrary CPU mask writes.

Expected behavior when re-arm is enabled:

```text
cold boot -> 6c/12t
systemd re-arms the unlock
current session remains 6c/12t
user chooses a warm reboot -> 8c/16t
```

The suite intentionally does **not** create an automatic reboot loop. A full cold
power cycle remains the recovery path if 8-core operation is unstable.

## GPU behavior

No intentional changes were made to WGP discovery, compute isolation, human
visual validation, combined verification, soak testing, or GPU boot persistence
safety gates from v0.4.0.

## Compatibility

The canonical command remains `./bc250-unlock`, with `./bc250-lab` retained as a
compatibility alias. Historical SteamOS internal paths containing
`bc250-wgp-lab` remain unchanged to avoid breaking existing state or GPU
persistence.
