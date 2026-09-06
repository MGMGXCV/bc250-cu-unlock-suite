# BC-250 CU Unlock Suite

**Discover. Test. Unlock.**

Experimental, reversible CU/WGP health testing and selective unlocking for the AMD BC-250 on Linux.

[Versión en español](README_ES.md)

BC-250 boards expose 24/40 GPU CUs by default. This toolkit does **not** blindly
turn on all 40. It discovers the board's real boot topology, tests each disabled
WGP pair (2 CUs) in isolation, adds a human visual-artifact gate, validates the
approved set together, and only then offers optional boot persistence.

> **Warning**
> Low-level GPU register writes can freeze the GPU or the whole machine. Save
> work before testing. Extra WGPs may be defective and may increase power and
> temperature. The toolkit is evidence-driven, not a hardware guarantee.

Use this tool responsibly. Keep a recovery path, never copy another board's WGP
profile, and do not install persistence until compute, visual, real-game and soak
tests are clean. See [SAFETY.md](SAFETY.md).

> **AI assistance disclosure**
> BC-250 CU Unlock Suite was developed with assistance from **OpenAI ChatGPT
> (GPT-5.6 Sol)** for research synthesis, test strategy, code/documentation
> drafting and packaging. Hardware observations and accept/reject decisions must
> remain human-validated. OpenAI does not sponsor or endorse this project. See
> [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).

## Why this exists

A compute-only test is not enough. During development we observed BC-250 WGPs
that passed a compute verifier but produced visible blue-square corruption in a
real Plasma desktop. The final workflow therefore requires **both** automated
compute correctness and a human real-desktop visual check before a WGP can be
included in the combined profile.

One WGP is two CUs; individual CUs cannot be routed independently by this
workflow.

## Supported platform paths

### CachyOS / Arch — validated path

This is the path used for the initial end-to-end hardware validation of the suite.

```bash
git clone <your-github-url>/bc250-cu-unlock-suite.git
cd bc250-cu-unlock-suite

./setup.sh --os cachyos
sudo ./bc250-unlock wizard
```

### SteamOS — experimental path

Real/Valve-style SteamOS is supported as a separate installation path. The WGP
routing method itself is the same, but SteamOS has an atomic/read-only host image,
so dependency installation and update recovery are handled differently.

```bash
git clone <your-github-url>/bc250-cu-unlock-suite.git
cd bc250-cu-unlock-suite

./setup.sh --os steamos
sudo ./bc250-unlock wizard
```

Or run plain `./setup.sh` and choose Auto/CachyOS/SteamOS interactively.

**Status:** SteamOS support is research-backed and aligns with current community
BC-250 SteamOS tooling, but it is intentionally marked experimental until this
exact discovery workflow has been validated on more SteamOS BC-250 systems.

After every SteamOS OS update, run:

```bash
sudo ./bc250-unlock steamos verify
# only if verify reports missing pieces:
sudo ./bc250-unlock steamos repair
```

See [docs/STEAMOS.md](docs/STEAMOS.md).

The wizard follows:

```text
preflight
  ↓
stock 24-CU baseline
  ↓
per-WGP compute scan
  ↓
per-WGP real-desktop visual scan
  ↓
combined approved-set verification
  ↓
live-only approved configuration
```

Nothing is made persistent by the wizard.

### Reuse an already-tested upstream checkout

If you are moving from an older BC-250 WGP Lab / CU Unlock Suite folder **after already testing a
board**, keep the exact upstream revisions you validated instead of updating them
right before persistence:

```bash
./setup.sh --reuse /path/to/previous-tool-folder
```

The runtime results do not need copying when you stay on the same platform because they live in the platform-specific state directory documented below.

## Optional graphical mode / Modo gráfico para usuarios menos experimentados

The CLI remains the primary interface, and v0.4.0 includes an optional bilingual
**Español / English** graphical guide:

```bash
./bc250-unlock gui
```

Start it **without sudo**. It opens a localhost-only browser UI with plain-language
instructions, the recommended workflow, status/recovery tools and SteamOS update
actions. Every hardware operation still launches the exact `bc250-unlock` CLI
command in a **visible terminal**, so warnings, `sudo`, progress and prompts remain
transparent. The GUI never implements GPU register writes itself.

For a normal application-menu entry:

```bash
./bc250-unlock gui-shortcut install
```

The graphical mode is optional; terminal users can ignore it completely. On SteamOS, use it from **Desktop Mode**. See
[docs/GUI.md](docs/GUI.md).


## Backward compatibility

The canonical command from v0.4.0 onward is `./bc250-unlock`. The legacy
`./bc250-lab` entry point is retained as a small forwarding alias so existing
notes/scripts do not break immediately. New documentation uses `bc250-unlock`.

For SteamOS compatibility, a few internal persistent paths still contain the old
`bc250-wgp-lab` directory name. They are intentionally retained so upgrades from
0.2/0.3 do not lose state or boot persistence. This is an implementation detail,
not the public project name.

## Main commands

```bash
./setup.sh                         # choose/auto-detect CachyOS or SteamOS
./bc250-unlock platform               # show detected platform
sudo ./bc250-unlock doctor           # hardware/dependency/topology check
sudo ./bc250-unlock wizard           # guided first-time workflow
sudo ./bc250-unlock baseline         # verify factory 24-CU map
sudo ./bc250-unlock scan             # compute-test each hidden WGP
sudo ./bc250-unlock visual           # visual-check compute-PASS WGPs
sudo ./bc250-unlock results          # result summary
sudo ./bc250-unlock apply            # apply only compute+visual approved WGPs
sudo ./bc250-unlock status           # live routing dashboard
sudo ./bc250-unlock stock            # return to factory routing live
sudo ./bc250-unlock recover          # classify pending hang/interruption
sudo ./bc250-unlock soak 30          # 30-minute combined compute soak
sudo ./bc250-unlock report           # Markdown report for sharing/issues
sudo ./bc250-unlock steamos verify   # SteamOS-only post-update health check
./bc250-unlock gui                    # optional bilingual graphical guide
```

### Persistence — only after real-world testing

```bash
sudo ./bc250-unlock persist status
sudo ./bc250-unlock persist install
```

`persist install` refuses to proceed unless the latest combined validation is a
`PASS` matching the currently approved WGP set. It then delegates the actual CU
table restore to `bc250-cu-live-manager`'s saved-table + systemd mechanism. On
SteamOS it additionally snapshots UMR/the manager into persistent `/opt` storage
and writes an atomic-update keep list for the `/etc` integration.

Rollback is intentionally simple:

```bash
sudo ./bc250-unlock persist remove
```

That removes boot restore and immediately returns the live GPU routing to the
factory boot-driver topology.

See [docs/PERSISTENCE.md](docs/PERSISTENCE.md).

## What counts as approved?

A candidate WGP is included only if all of these are true:

```text
latest compute result = PASS
latest visual result  = PASS_VISUAL
manual denylist       = no entry
```

A visible artifact always overrides a synthetic PASS.

The visual phase enables one candidate WGP on top of the board's stock 24-CU
map, gives you a timed window to use the real desktop, restores stock **before**
asking for your verdict, and records the answer.

Recommended actions during the window: move the pointer quickly, open/close
menus, drag windows, hover menus, minimize/maximize, and reproduce any workload
that has previously exposed corruption.

## Irregular factory maps are supported

Do not assume every board uses WGP0/1/2 in every shader-array row. The probe
parses the **amdgpu boot CU bitmap** shown by the live manager and derives the
actual eight disabled WGP candidates for that board. This matters on boards with
scattered harvesting patterns.

Profiles are **board-specific**. Never copy another person's WGP list as a
shortcut.

## Example result from one tested board

This is documentation, **not a profile to reuse**:

```text
Factory: 24 CUs

Compute + visual good:
  0.0.3  0.0.4  1.0.3  1.0.4  1.1.4

Rejected:
  0.1.3  visual corruption (blue squares)
  0.1.4  visual corruption (blue squares)
  1.1.1  compute verifier failure

Validated combined target:
  24 + (5 WGP × 2 CU) = 34/40 CUs
```

The same board had an irregular stock row where `1.1.3` was factory-active and
`1.1.1` was factory-disabled; the compute verifier later found `1.1.1` faulty.
See [examples/example-34cu-report.md](examples/example-34cu-report.md).

## State and recovery

Runtime state is platform-specific:

```text
CachyOS / Arch: /var/lib/bc250-probe/
SteamOS:        /home/.steamos/offload/var/lib/bc250-wgp-lab/
```

The SteamOS location lives on the shared `/home` storage so discovery results are
not tied to one atomic OS slot.

Before a risky live write, the probe syncs a pending marker. If a WGP hard-locks
the machine, reboot and run:

```bash
sudo ./bc250-unlock recover
sudo ./bc250-unlock results
```

The reboot returns live-only routing to the boot topology unless persistence was
explicitly installed.

## Optional offscreen graphics verifier

The repository retains an experimental EGL/GLES framebuffer readback test:

```bash
sudo ./bc250-unlock gfx baseline
sudo ./bc250-unlock gfx scan
```

It can detect some graphics faults automatically, but it is **not** a substitute
for the visual gate: a known bad WGP during development passed offscreen readback
while still corrupting the physical display.

## CPU helper

GPU WGP testing and CPU-core unlocking are separate mechanisms. An optional CPU
helper is included for research:

```bash
sudo ./bc250-unlock cpu status
sudo ./bc250-unlock cpu unlock
# warm reboot, then:
sudo ./bc250-unlock cpu quick
```

Do not mix CPU unlocking, GPU WGP discovery, overclocking, and undervolting in a
single diagnostic step. Change one variable at a time.

## Upstream projects

This toolkit intentionally fetches rather than vendors its two key upstream
projects:

- https://github.com/WinnieLV/bc250-cu-live-manager — live UMR routing,
  dashboard and optional boot restore.
- https://github.com/duggasco/bc250-40cu-unlock — BC-250 CU research and the
  Vulkan compute verifier.

Current `bc250-cu-live-manager` documentation states that its live workflow does
not require a kernel patch and that boot persistence consists of saving the
current table and installing its systemd service.

See [THIRD_PARTY.md](THIRD_PARTY.md).

## Documentation

- [Methodology and safety model](docs/METHODOLOGY.md)
- [Persistence and rollback](docs/PERSISTENCE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Sharing results / reports](docs/REPORTS.md)
- [SteamOS platform notes](docs/STEAMOS.md)
- [Optional graphical mode / beginner guide](docs/GUI.md)
- [Publishing on GitHub](docs/GITHUB.md)
- [Safety and responsibility](SAFETY.md)
- [Technical references and credits](docs/REFERENCES.md)
- [Licensing notes](docs/LICENSING.md)
- [Acknowledgements and AI assistance](ACKNOWLEDGEMENTS.md)
- [Contributing](CONTRIBUTING.md)

## License

**MIT is the recommended/default license for BC-250 CU Unlock Suite-authored files.** It
is permissive, widely understood and includes an AS-IS/no-warranty clause.
Fetched upstream projects remain under their own licenses and are not relicensed
by this repository. In particular, `duggasco/bc250-40cu-unlock` advertises
GPL-2.0, while `bc250-cu-live-manager` is fetched separately rather than vendored
because an explicit upstream license was not advertised when this release was
reviewed.

See [LICENSE](LICENSE), [THIRD_PARTY.md](THIRD_PARTY.md) and
[docs/LICENSING.md](docs/LICENSING.md).

### Already using a persistent profile

If boot persistence is enabled, graphical mode switches to **protected persistent mode**. The diagnostic workflow (wizard, baseline, scans, combined validation and soak) is disabled because the CLI intentionally refuses to probe while the boot-restore service is active. Status, results, reports and persistence management remain available. To test hidden WGPs again, remove persistence first and reboot/return to a clean stock routing.
