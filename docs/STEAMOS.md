# SteamOS support

> **Compatibility note (v0.4.0):** internal SteamOS paths such as
> `/home/.steamos/offload/var/lib/bc250-wgp-lab` and `/opt/bc250-wgp-lab` keep
> the historical directory name intentionally. This preserves upgrades from
> 0.2/0.3 and does not represent the public project name.

SteamOS support is a **separate platform path**, not a claim that SteamOS behaves
like ordinary Arch Linux.

## Status

- CachyOS/Arch: end-to-end WGP discovery has been validated on real BC-250 hardware.
- SteamOS: experimental in this project until the same workflow is validated on
  more BC-250 SteamOS machines.
- The underlying live WGP method is already used by current BC-250 SteamOS
  community projects; the experimental part here is this suite's installer,
  state layout, validation workflow and update-repair integration.

This path targets **real/Valve-style SteamOS** with `steamos-readonly`, `pacman`
and systemd. It is not the Bazzite/rpm-ostree path.

If the **same physical board** is migrated from CachyOS to SteamOS, do not blindly
import the old PASS/visual state as a trusted persistent profile. The silicon is
the same, but the kernel/Mesa/compositor stack changed; rerun discovery/combined
validation (or at minimum stock baseline, the known approved WGPs, combined
compute and the real-desktop visual gate) before enabling persistence on the new
OS.

## Why SteamOS needs a separate installer

SteamOS uses an atomic/read-only system image. Packages added to the host under
`/usr` can be lost when the OS image is replaced. The suite therefore:

1. temporarily disables read-only mode only while installing missing test tools;
2. always re-enables read-only mode with an EXIT trap;
3. stores board discovery/results under the shared `/home/.steamos/offload` tree;
4. snapshots the validated UMR executable/database material and live-manager helper
   under `/opt/bc250-wgp-lab` when boot persistence is installed;
5. installs an `/etc/atomic-update.conf.d/bc250-wgp-lab.conf` keep list for the
   saved CU table and systemd unit;
6. provides a post-update `verify`/`repair` workflow instead of trying to modify
   packages automatically during boot.

The persistent boot profile does not intentionally depend on `/usr/bin/umr`: `persist install` snapshots the validated UMR executable (and available database material) under persistent `/opt`. Host-side development/test packages under `/usr` can still disappear after an OS update, so `steamos verify/repair` remains necessary before rerunning diagnostics. If the persistent helper itself becomes incompatible with a future SteamOS userspace/kernel, boot restore should fail rather than attempting an unattended package install at boot.

## Install

From Desktop Mode:

```bash
git clone https://github.com/MGMGXCV/bc250-cu-unlock-suite.git
cd bc250-cu-unlock-suite
./setup.sh --os steamos
sudo ./bc250-unlock doctor
sudo ./bc250-unlock wizard
```

The SteamOS bootstrap checks/installs:

```text
git base-devel gcc python pciutils libdrm glslang vulkan-headers vulkan-icd-loader
vulkan-radeon stress-ng mesa libglvnd zstd UMR
```

Do **not** use `pacman -Syu` as a way to update SteamOS. Update SteamOS through
its normal update mechanism.

## State

SteamOS state defaults to:

```text
/home/.steamos/offload/var/lib/bc250-wgp-lab/
```

Override only for development/testing with:

```bash
BC250_STATE_DIR=/some/path ...
```

## Boot persistence

After compute, visual, combined and soak validation:

```bash
sudo ./bc250-unlock persist install
```

On SteamOS the suite still uses the upstream live-manager saved table, but it also:

- snapshots UMR under `/opt/bc250-wgp-lab/umr/` and rewrites the saved table to use it;
- pins the manager script to `/opt/bc250-wgp-lab/bin/bc250-cu-live-manager`;
- rewrites the systemd `ExecStart` to that persistent helper;
- writes `/etc/atomic-update.conf.d/bc250-wgp-lab.conf` containing the CU config,
  unit, enablement link and keep-list itself.

Rollback remains:

```bash
sudo ./bc250-unlock persist remove
```

## After a SteamOS update

Run this before assuming the unlock still works:

```bash
sudo ./bc250-unlock steamos verify
```

It checks the tools required by the compute verifier, UMR, Vulkan headers/loader,
the live manager, saved table and boot service.

If anything is missing:

```bash
sudo ./bc250-unlock steamos repair
sudo ./bc250-unlock steamos verify
```

`repair` reinstalls/checks host dependencies through the SteamOS bootstrap and,
when a saved CU table exists, repairs the service without intentionally changing
the saved WGP mask.

If the kernel/Mesa update changes actual GPU behaviour, do not assume the old
profile is still valid. Re-run at least:

```bash
sudo ./bc250-unlock status
sudo ./bc250-unlock soak 10
```

and perform a real-game/desktop visual check before relying on it.

## Atomic-update keep list

Inspect what the suite asks SteamOS to retain:

```bash
sudo ./bc250-unlock steamos keep-status
```

On images that provide `holo-sync-var`, the command also shows matching dry-run
information when available.

## CPU unlock / re-arm on SteamOS

The v0.5.0 CPU CLI is available on SteamOS through the same separately fetched
live-manager, but **CPU re-arm on SteamOS remains experimental** until validated
on real SteamOS BC-250 hardware.

When advanced CPU re-arm is enabled, the suite places a local runtime copy of the
live-manager under `/opt/bc250-wgp-lab/bin/bc250-cpu-rearm-manager` and uses a
separate `/etc/atomic-update.conf.d/bc250-cpu-rearm.conf` keep list for its
systemd integration. It still never reboots automatically; after a cold boot a
user-initiated warm reboot is required before 8c/16t becomes active.

## Known limitations

- SteamOS images/channels change more quickly than CachyOS/Arch package layouts.
- Host packages installed by `pacman` may disappear after an atomic update.
- The keep list protects the CU service/config integration; it does not guarantee
  that a future kernel, Mesa or UMR build behaves identically.
- This project does not install BC-250 ACPI fixes, governor tuning, patched Mesa,
  or audio fixes on SteamOS. CPU unlock/re-arm is separate from the GPU workflow
  and remains experimental on SteamOS even though the CachyOS CPU path has been
  validated on the reference board.
- Bazzite is not currently the same path; it uses rpm-ostree and should get its
  own installer rather than being treated as SteamOS.

## Community references

At the time this platform path was added, current community projects documented
real SteamOS on BC-250, runtime CU/WGP management and SteamOS atomic-update
persistence/recovery. Those projects are useful compatibility references but are
not vendored by this repository.

- `rpf16rj/bc250-steamos-real-toolkit`
- `keyboardspecialist/bc250-steamos`
- `WinnieLV/bc250-cu-live-manager`