# Release notes — v0.4.0

# BC-250 CU Unlock Suite

**Discover. Test. Unlock.**

Version 0.4.0 is the first release under the new public project name
**BC-250 CU Unlock Suite**. It packages the workflow validated on a real BC-250
into a clearer name aimed at users searching specifically for CU unlocking.

## Highlights

- New canonical command: `./bc250-unlock`.
- `./bc250-lab` remains as a compatibility alias.
- Bilingual beginner GUI rebranded to BC-250 CU Unlock Suite.
- CLI headers, launcher, reports, docs and GitHub templates use the new identity.
- MIT licensing, safety warnings, upstream credits and ChatGPT assistance
  disclosure remain explicit.
- CachyOS/Arch remains the hardware-validated path. SteamOS remains experimental.

## Compatibility

Existing SteamOS state/persistence paths containing the historical
`bc250-wgp-lab` name are intentionally retained internally. Renaming those paths
would create needless migration risk. They are not the public project name.

## Safety

This is still an experimental low-level hardware tool. Never copy another
board's WGP profile, save work before probing, treat visible artifacts as a
failure even if synthetic tests pass, and only enable persistence after real
workloads plus a clean soak test.

## Validated reference result

The reference development board was validated at 34/40 routed CUs after rejecting
three faulty hidden WGPs, including two that caused visible blue-square corruption
and one that failed compute verification. This is an example only, not a profile
to reuse.
