# Methodology and safety model

## Goal

Find the largest **tested** WGP set on one BC-250 without assuming that every
harvested block is healthy and without making exploratory settings persistent.

## Discovery unit

The live routing controls operate at WGP granularity. One WGP is two CUs. The
probe therefore treats each boot-map-disabled WGP as one candidate.

## Board-local topology

`bc250-gpu-probe.sh` parses the live-manager dashboard. `D+` / `D!` cells belong
to the WGP topology discovered by amdgpu at boot; `S+` / `--` cells are outside
that boot topology. The tool requires 12 factory WGPs (24 CUs) and 8 candidate
WGPs (16 CUs) but does not assume where those 12 factory WGPs are located.

## Test stages

### 1. Stock baseline

Factory routing is restored and the Vulkan compute verifier must pass before any
candidate is blamed for a later failure.

### 2. Isolated compute test

For each candidate:

1. restore factory routing;
2. sync a pending crash marker;
3. enable exactly one candidate WGP (+2 CUs);
4. run the compute verifier;
5. inspect kernel logs and temperature;
6. restore factory routing;
7. record the result.

### 3. Human real-desktop visual test

Compute-PASS candidates are enabled one at a time. The operator exercises the
actual desktop and watches for corruption. Factory routing is restored before
asking for the verdict.

This stage exists because a graphics fault can be visible even when a compute
verifier or offscreen readback test passes.

### 4. Combined validation

Only candidates with compute `PASS`, visual `PASS_VISUAL`, and no denylist entry
are enabled together. The heavier compute verifier runs, then a second manual
visual window is performed on the complete candidate set.

### 5. Real workload + soak

The combined set should survive real games/applications and an optional long
compute soak before boot persistence is considered.

## Recovery model

Exploration is live-only. A pending marker records which candidate was active
before a risky write. If the machine hard-freezes, reboot before running another
test and use `sudo ./bc250-unlock recover` to attribute the interrupted test.

## Thermal model

The default automated cutoff is 95 C (`BC250_MAX_TEMP_C=95`). This is an
emergency test cutoff, not a recommended continuous target. Stable long-term
operation should have meaningful thermal margin below it.

## Things intentionally not automated

A monitor-visible artifact is treated as stronger evidence than a synthetic
PASS. Internal CRC/readback approaches do not necessarily observe every stage of
the physical display path, so the final desktop gate remains human-reviewed.
