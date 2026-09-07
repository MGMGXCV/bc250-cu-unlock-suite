# Troubleshooting

## `pending marker exists; run recover`

A prior risky test did not complete its normal cleanup. Run:

```bash
sudo ./bc250-unlock recover
./bc250-unlock results
```

If the pending marker came from a previous boot, the result is recorded as a
hard hang/reboot candidate. If it is from the same boot, it is recorded as an
interrupted test.

## `active_cu_number=24` while the dashboard says 34/40

For live routing, the module's boot-time CU count can remain 24. Use the
live-manager's `CUs active & routed` line and WGP table as the runtime routing
source of truth.

## Irregular factory layout warning

This is not automatically an error. Some boards have a scattered boot topology.
The suite intentionally derives candidates from that board's own amdgpu boot map.

## A WGP passes compute but shows colored squares/blocks

Mark the visible artifact as a failure. The visual result overrides compute PASS.
Run the visual scan or explicitly mark it through the probe. Do not include that
WGP in a persistent profile.

## Hard freeze

Do not immediately repeat the same test. Reboot, run `recover`, inspect the
summary, then continue. Save important work before every exploratory scan.

## Temperature cutoff

Improve cooling, remove an overclock/undervolt, and repeat the stock baseline
before continuing. Do not diagnose WGP health while simultaneously tuning
frequency/voltage.

## Persistence is enabled and probing refuses to start

That is intentional. Exploratory probing refuses to run while the upstream boot
restore service is enabled. Remove persistence first:

```bash
sudo ./bc250-unlock persist remove
```

Then reboot if you want a completely clean factory-started session.

## SteamOS: unlock disappeared after an OS update

First check the platform integration instead of rerunning discovery blindly:

```bash
sudo ./bc250-unlock steamos verify
```

If `/usr` host packages such as UMR/build tools disappeared, repair them through
the SteamOS-aware bootstrap:

```bash
sudo ./bc250-unlock steamos repair
sudo ./bc250-unlock steamos verify
```

A missing host tool should fail safe: the GPU remains on its boot/factory routing
rather than the toolkit trying to modify SteamOS packages unattended during boot.

## SteamOS: boot service/config disappeared

Inspect:

```bash
sudo ./bc250-unlock persist status
sudo ./bc250-unlock steamos keep-status
```

The saved table and systemd integration are protected through an atomic-update
keep list, while the manager/UMR boot helpers live under persistent `/opt`. If an
update still leaves a partial installation, run `steamos repair` and verify again.
Do not copy a saved table from another BC-250 as a shortcut.

## SteamOS: `pacman` package changes vanished

That is expected behavior for packages added to the atomic root image. Use
SteamOS's normal OS updater for the operating system itself; do not use
`pacman -Syu` to turn SteamOS into ordinary rolling Arch. Re-run
`sudo ./bc250-unlock steamos repair` when the suite reports missing host dependencies.

## CPU is back to 6c/12t after power was removed

That is expected. The CPU core-presence unlock is volatile. Check:

```bash
sudo ./bc250-unlock cpu status
```

With automatic re-arm disabled, run `cpu unlock` again and then choose a warm
reboot. With automatic re-arm enabled, check:

```bash
sudo ./bc250-unlock cpu rearm status
```

If it says the unlock was re-armed this boot, the current session will still be
6c/12t until you perform a warm reboot. The re-arm service never reboots the
machine automatically.

## `cpu rearm enable` refuses because the deep safety gate is missing

Run the full validation while 8c/16t is active:

```bash
sudo ./bc250-unlock cpu deep
```

Re-arm requires PASS records for physical cores 3 and 7 plus the all-thread stage
from the same deep-test log. This gate is intentional and should not be bypassed.

## CPU re-arm service failed

Inspect the current boot:

```bash
sudo systemctl status bc250-cpu-rearm.service
sudo journalctl -u bc250-cpu-rearm.service -b
```

Do not add an automatic reboot workaround. If the 8-core state itself is unstable,
perform a full cold power cycle to return CPU enumeration to stock 6c/12t, then
disable re-arm:

```bash
sudo ./bc250-unlock cpu rearm disable
```
