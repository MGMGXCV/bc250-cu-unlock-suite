# Release notes — v0.5.1

# BC-250 CU Unlock Suite

**Discover. Test. Unlock.**

Version 0.5.1 is a small maintenance release that improves GPU status reporting
in the graphical interface without changing the unlock, validation, CPU re-arm,
or persistence workflows.

## Highlights

- The GUI still prefers the real live CU query whenever cached/passwordless sudo
  is available.
- If that live query is unavailable, and `bc250-cu-live-manager.service` is both
  enabled and active, the GUI now reads the saved boot profile from
  `/etc/bc250-cu-live-manager.conf` and derives the routed CU count from its four
  `BC250_WGP_MASKS` entries.
- This fallback is read-only: it does not grant the GUI extra privileges, enable
  passwordless sudo, or perform GPU register writes.
- If the service is not active, the GUI does not treat the saved profile as live
  routing state.

## Hardware validation

The reference development board uses the persisted WGP masks:

```text
0x1f,0x07,0x1f,0x1d
```

That profile corresponds to 34/40 routed CUs. When the GUI is launched normally
from the KDE Plasma application shortcut, with no cached sudo session, the status
card now reports `34/40` instead of an unavailable dash.

This result is board-specific. The suite calculates the count from each board's
own saved profile and does not copy or assume the reference board's masks.

## Safety and compatibility

No intentional changes were made to:

- WGP discovery or selective GPU unlocking;
- compute, human visual, combined, or soak validation;
- GPU boot-persistence installation or rollback;
- CPU 6c/12t -> 8c/16t unlock;
- CPU quick/deep validation or automatic re-arm behavior;
- SteamOS persistent-path compatibility.

The canonical command remains `./bc250-unlock`, with `./bc250-lab` retained as a
compatibility alias.
