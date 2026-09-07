# Third-party tools, licenses and compatibility references

BC-250 CU Unlock Suite intentionally does **not** vendor the upstream register manager or
compute-verifier repository in release archives. `setup.sh` fetches them into
`./upstream/` so their source, history and licensing remain separate.

Last reviewed: **2026-09-07**.

## Runtime upstream dependencies

### WinnieLV / `bc250-cu-live-manager`

https://github.com/WinnieLV/bc250-cu-live-manager

Used for live WGP routing, status/dashboard output, UMR integration, stock
restore, optional boot-table persistence, and the known volatile BC-250 CPU
core-presence unlock used by `cpu unlock` / advanced CPU re-arm. When CPU re-arm
is enabled, the suite installs a local runtime copy of the already-fetched
live-manager on that machine so systemd does not depend on the checkout path.
That copy is created locally at enable time and is not included in release archives.

At the time of this review, the repository did not advertise an explicit
software license in its repository metadata/README. BC-250 CU Unlock Suite therefore
fetches it separately and **does not redistribute or relicense it**. Before
bundling or redistributing that project, review its current upstream licensing
status or obtain permission from its author(s).

### duggasco / `bc250-40cu-unlock`

https://github.com/duggasco/bc250-40cu-unlock

Used as the core BC-250 CU research reference and as the source of the Vulkan
compute verifier fetched during setup.

The upstream repository advertises **GPL-2.0**. Any fetched GPL code remains
under its upstream license; BC-250 CU Unlock Suite's MIT license does not replace it.

## Tooling

### UMR — AMDGPU User Mode Register debugger

https://gitlab.freedesktop.org/tomstdenis/umr

Used indirectly by the live-manager for AMDGPU register inspection/writes.
Package/source licensing remains that of UMR and the distribution packaging it.

## SteamOS compatibility/recovery references

These are not vendored runtime dependencies:

- https://github.com/rpf16rj/bc250-steamos-real-toolkit
- https://github.com/keyboardspecialist/bc250-steamos

They provide useful evidence that real SteamOS on BC-250 can support runtime
CU/WGP management and that atomic-update recovery needs separate handling.
BC-250 CU Unlock Suite's own SteamOS workflow remains experimental until validated on
additional hardware.

## Documentation/reference sources

See [docs/REFERENCES.md](docs/REFERENCES.md) for the fuller research trail.

## License boundary

The repository's MIT license applies only to files authored as part of BC-250
CU Unlock Suite. It does not relicense fetched third-party software.

GitHub's licensing guidance notes that source published without an explicit
license remains protected by default copyright rules rather than becoming
openly redistributable merely because it is public:
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
