# Persistence and rollback

> **Compatibility note (v0.4.0):** internal SteamOS paths such as
> `/home/.steamos/offload/var/lib/bc250-wgp-lab` and `/opt/bc250-wgp-lab` keep
> the historical directory name intentionally. This preserves upgrades from
> 0.2/0.3 and does not represent the public project name.

Persistence should be the **last** step, after combined validation and real-world
use. Avoid updating the live-manager/verifier between the final validation and
persistence. If migrating from an older tool folder, use
`./setup.sh --reuse /path/to/old-bc250-unlock` to preserve the revisions you actually
tested.

## Safety gate

`sudo ./bc250-unlock persist install` requires:

- a cached board-local factory/candidate topology;
- one or more WGPs with both compute `PASS` and `PASS_VISUAL`;
- no manual denylist entry for the selected WGPs;
- latest `COMBINED` result = `PASS`;
- that combined PASS must match the current approved CU count;
- no pending crash marker.

If the visual/compute result set changes, rerun `sudo ./bc250-unlock apply` before
persistence.

## GPU persistence vs CPU re-arm

This document mainly describes **GPU WGP boot persistence**. v0.5.0 also offers
an advanced CPU **re-arm** service, but it is intentionally named differently:

```bash
sudo ./bc250-unlock cpu rearm status
sudo ./bc250-unlock cpu rearm enable
sudo ./bc250-unlock cpu rearm disable
```

CPU re-arm is OFF by default and requires a complete `cpu deep` PASS. It does not
make 8c/16t survive a full cold power cycle in the same way the GPU table survives
a reboot. After a cold boot Linux still starts at 6c/12t; the service only re-arms
the volatile CPU mask so the user can choose a subsequent **warm reboot** to
activate 8c/16t. The service never performs that reboot automatically.

See [CPU.md](CPU.md).

## How persistence is implemented

The wrapper does not invent another register-writing boot service. It uses the
boot restore already provided by `bc250-cu-live-manager`:

1. restore stock live;
2. enable the approved WGP list live;
3. verify the expected routed CU count;
4. ask the upstream manager to save the **current live table**;
5. ask the upstream manager to install/enable its systemd service;
6. save a local audit profile in the platform-specific suite state directory.

The upstream saved table is stored in `/etc/bc250-cu-live-manager.conf`.

State/audit locations:

```text
CachyOS / Arch: /var/lib/bc250-probe/
SteamOS:        /home/.steamos/offload/var/lib/bc250-wgp-lab/
```

## CachyOS / Arch

No extra persistence layer is needed beyond the upstream saved table + systemd
service. Install with:

```bash
sudo ./bc250-unlock persist install
sudo ./bc250-unlock persist status
```

Then reboot when convenient and verify:

```bash
sudo ./bc250-unlock status
```

The final dashboard line should show the expected routed CU count.

## SteamOS

SteamOS has an atomic/read-only root image, so `persist install` adds several
platform-specific protections while keeping the same validated WGP masks:

- snapshots the UMR executable used by the validated profile under
  `/opt/bc250-wgp-lab/umr/`;
- snapshots an extracted UMR database when available, or the packaged database
  archive when that is what the current UMR install provides;
- rewrites the saved upstream config so the boot service uses the persistent UMR
  snapshot rather than relying only on `/usr/bin/umr`;
- pins the live-manager helper at
  `/opt/bc250-wgp-lab/bin/bc250-cu-live-manager`;
- writes `/etc/atomic-update.conf.d/bc250-wgp-lab.conf` so the saved CU table,
  systemd unit and enablement link are requested to survive atomic updates.

SteamOS offloads `/opt` to persistent `/home` storage on the Valve-style image,
which is why privileged boot helpers are kept there instead of in `/usr`.

After every SteamOS update, verify before assuming the unlock is still healthy:

```bash
sudo ./bc250-unlock steamos verify
```

If host tools were replaced/removed:

```bash
sudo ./bc250-unlock steamos repair
sudo ./bc250-unlock steamos verify
```

The repair path does not intentionally change the saved WGP mask. It refreshes
host dependencies/UMR and repairs the boot integration around the already-saved
table.

See [STEAMOS.md](STEAMOS.md) for the full platform notes and limitations.

## Rollback

From a working boot:

```bash
sudo ./bc250-unlock persist remove
```

This asks the upstream manager to uninstall its boot restore and immediately
returns live routing to the factory boot-driver topology. On SteamOS it also
removes this project's `/opt` UMR/manager snapshots and its atomic-update keep
list.

If a persistent profile prevents a normal graphical session, use a TTY/recovery
shell and remove the service there. The underlying upstream manager also exposes
`uninstall-service` directly.

## Do not share saved masks between boards

A persistent mask is specific to the silicon that was tested. Share the toolkit
and the result report, **not** the boot profile as a universal setting.