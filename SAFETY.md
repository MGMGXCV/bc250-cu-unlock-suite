# Safety and responsibility

BC-250 CU Unlock Suite is an **experimental hardware research tool**. It can write
low-level AMDGPU routing registers and can intentionally expose factory-disabled
GPU WGPs. Some disabled WGPs may be defective.

## Use responsibly

By running hardware-changing actions, you accept that testing may:

- freeze the GPU or the whole machine;
- corrupt the display or produce incorrect compute results;
- lose unsaved work;
- increase power draw and temperature;
- require a reboot or a return to the factory 24-CU routing;
- reveal instability that synthetic tests do not catch.

Before testing:

1. Save your work.
2. Use stable cooling and power.
3. Keep a known recovery/rollback path.
4. Test one variable at a time; do not combine WGP discovery with CPU unlock,
   overclocking or undervolting.
5. Never copy another board's WGP profile. Discover and validate the topology of
   the physical board in front of you.
6. Treat visible corruption as a failure even if an automated verifier says
   `PASS`.
7. Do not install boot persistence until the combined profile has passed
   compute, visual, real-workload and soak testing.

The project includes safety gates and rollback helpers, but **no test can prove
that a harvested WGP is healthy under every possible workload**.

## Warranty and liability

The repository is provided under the MIT License and therefore on an **AS IS**
basis without warranty. This safety document is practical guidance, not a
replacement for the license text and not legal advice.

No affiliation or endorsement by AMD, Sony, Valve, Arch Linux, CachyOS, KDE,
OpenAI, or the maintainers of referenced upstream projects is implied.
