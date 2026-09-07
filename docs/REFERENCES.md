# Technical references and credits

This file records the main public sources used to design, verify or contextualize
BC-250 CU Unlock Suite. The project links to/fetches upstream tools rather than claiming
their work as its own.

Last reviewed: **2026-09-07**.

## Core BC-250 GPU work

### duggasco — BC-250 40 CU Unlock

https://github.com/duggasco/bc250-40cu-unlock

Used as the primary research reference for:

- BC-250 `gfx1013` 24/40-CU topology;
- the need to modify both CU enumeration and SPI WGP dispatch state;
- WGP granularity (2 CUs per WGP);
- selective WGP/CU health testing methodology;
- the Vulkan compute verifier fetched by this toolkit.

The upstream repository advertises **GPL-2.0**. Its fetched code remains under
that license and is not relicensed by BC-250 CU Unlock Suite.

### WinnieLV — BC-250 CU Live Manager

https://github.com/WinnieLV/bc250-cu-live-manager

Used at runtime for:

- reading the real `amdgpu` boot topology;
- live WGP routing through UMR;
- the status/dashboard representation;
- returning to stock routing;
- saving/applying a selected boot table through systemd;
- the volatile CPU core-presence unlock used by the suite's 6c/12t -> 8c/16t workflow and advanced re-arm service.

At the time this release was prepared, the repository did not advertise an
explicit software license in its repository metadata/README. BC-250 CU Unlock Suite
therefore **does not vendor or relicense it**; setup fetches it as a separate
upstream project. Review the upstream repository before redistributing it.

GitHub's licensing documentation explains that publishing source without an
explicit license does not automatically grant general reuse/distribution rights:
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository

## AMD register tooling

### UMR — User Mode Register debugger for AMDGPU

Upstream/project home referenced by UMR documentation:
https://gitlab.freedesktop.org/tomstdenis/umr

UMR provides userspace AMDGPU register inspection/write facilities. BC-250 CU Unlock Suite does not implement register access itself; the live-manager uses UMR.

## Community documentation

### AMD BC-250 documentation

https://github.com/elektricM/amd-bc250-docs

Useful cross-reference for BC-250 system details, CU unlock notes and community
field observations. The original upstream projects above remain the primary
source for the actual routing implementation used by this toolkit.

## Graphics/compute API references

### Khronos Vulkan documentation

https://docs.vulkan.org/

https://registry.khronos.org/vulkan/

Used as general reference for Vulkan compute/shader behavior and terminology.
The compute correctness test itself is fetched from duggasco's repository.

## SteamOS compatibility references

The SteamOS path was informed by public BC-250/SteamOS work including:

- https://github.com/rpf16rj/bc250-steamos-real-toolkit
- https://github.com/keyboardspecialist/bc250-steamos

These are compatibility/recovery references, not vendored runtime dependencies.
The SteamOS path in BC-250 CU Unlock Suite remains experimental until it receives broader
hardware validation.

## Licensing references

- Open Source Initiative — MIT License:
  https://opensource.org/license/mit
- GitHub — Licensing a repository:
  https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository

## Attribution principle

If a future contribution copies or substantially adapts code from an upstream
project rather than merely invoking it, contributors must preserve the upstream
copyright/license requirements and update `THIRD_PARTY.md` and this file.
