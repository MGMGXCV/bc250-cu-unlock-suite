# CPU unlock — 6c/12t to 8c/16t

BC-250 CU Unlock Suite v0.5.0 promotes CPU-core unlocking from a hidden research
helper to a documented first-class workflow. GPU CU/WGP routing and CPU-core
unlocking remain separate mechanisms; test one variable at a time.

## What the CPU unlock does

The BC-250 normally enumerates 6 CPU cores / 12 threads. The upstream
`bc250-cu-live-manager` implements the known volatile SMU operation that raises
the core-presence mask from `0x77` to `0xFF`. BC-250 CU Unlock Suite delegates the
actual SMU operation to that upstream implementation rather than duplicating or
inventing mask writes.

```bash
sudo ./bc250-unlock cpu status
sudo ./bc250-unlock cpu unlock
sudo systemctl reboot
sudo ./bc250-unlock cpu status
```

A successful warm reboot should enumerate 8 cores / 16 threads. The unlock is
volatile: a full cold power cycle returns the CPU to its factory enumeration.

The suite never reboots automatically from the non-interactive CPU helper. You
choose when to perform the warm reboot.

## Validate the two newly exposed cores

Do not treat `16 threads present` as sufficient evidence that the extra cores are
healthy. The suite identifies physical cores 3 and 7 and tests them separately.

Quick validation:

```bash
sudo ./bc250-unlock cpu quick
```

This runs approximately:

- physical core 3: 30 seconds;
- physical core 7: 30 seconds;
- all online threads: 60 seconds.

Deep validation:

```bash
sudo ./bc250-unlock cpu deep
```

This runs approximately:

- physical core 3: 300 seconds;
- physical core 7: 300 seconds;
- all online threads: 600 seconds.

The tests use `stress-ng --verify`, bind the per-core stages with `taskset`, and
check the kernel journal for hardware/MCE/lockup indicators. Results are stored
under the platform state directory in `cpu-results.tsv` with detailed logs under
`logs/`.

A PASS is evidence, not a guarantee. Test real applications and games as well.

## Automatic CPU re-arm — advanced, OFF by default

The CPU unlock itself cannot make 8c/16t survive a full cold power cycle. v0.5.0
therefore offers an optional **re-arm** service, deliberately separated from the
normal unlock workflow.

```bash
sudo ./bc250-unlock cpu rearm status
sudo ./bc250-unlock cpu rearm enable
sudo ./bc250-unlock cpu rearm disable
```

`rearm enable` is refused until one complete `cpu deep` run contains PASS results
for physical core 3, physical core 7 and the all-thread stage from the same test
log.

### What re-arm actually changes

With re-arm **disabled** (the default):

```text
cold boot -> 6c/12t
run cpu unlock manually
warm reboot -> 8c/16t
```

With re-arm **enabled**:

```text
cold boot -> 6c/12t
systemd automatically re-arms the 0xFF mask
current session is STILL 6c/12t
YOU choose a warm reboot -> 8c/16t
```

The switch therefore only saves the manual `cpu unlock` step after a cold boot.
It does **not** remove the warm-reboot requirement.

The re-arm service never calls `reboot`, `shutdown`, `poweroff`, or an equivalent
automatic restart action. This is intentional: the user controls when the extra
cores become active.

## Recovery

If the machine is unstable after activating 8c/16t, do not keep retrying warm
reboots. Power the system off completely, remove input power long enough for a
true cold start, then boot again. The volatile CPU mask should return to the
factory 6c/12t enumeration.

Disabling automatic re-arm does not forcibly hide cores that are already active;
it only prevents future cold boots from being re-armed automatically.

## Interaction with the GPU profile

CPU unlock/re-arm and GPU WGP persistence are independent. A board may therefore
run, for example, a validated persistent GPU profile while the CPU remains stock,
or use 8c/16t while retaining the same validated GPU routing.

Do not combine first-time CPU validation with first-time hidden-WGP discovery,
overclocking or undervolting. Establish one known-good state before changing the
next variable.

## Current validation status

The v0.5.0 CPU workflow was exercised on the reference development BC-250 with:

- 8c/16t enumeration after a warm reboot;
- quick PASS on physical cores 3 and 7 plus all threads;
- deep PASS on physical cores 3 and 7 plus all threads;
- real-game testing without observed CPU instability;
- cold power recovery back to 6c/12t;
- subsequent re-unlock back to 8c/16t.

This is one board-specific validation result, not a guarantee for every BC-250.
