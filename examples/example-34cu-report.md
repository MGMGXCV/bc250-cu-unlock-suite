# Example: one irregular-map BC-250 that validated at 34/40 CUs

> Example only. Do not copy this WGP list to another board.

## Factory boot topology

```text
SE0.SH0: WGP0 WGP1 WGP2
SE0.SH1: WGP0 WGP1 WGP2
SE1.SH0: WGP0 WGP1 WGP2
SE1.SH1: WGP0 WGP2 WGP3
```

The last row is irregular: WGP3 is factory-active and WGP1 is factory-disabled.

## Candidate classification

| WGP | Compute | Real-desktop visual | Final |
|---|---|---|---|
| `0.0.3` | PASS | PASS_VISUAL | approved |
| `0.0.4` | PASS | PASS_VISUAL | approved |
| `0.1.3` | PASS | blue-square corruption | rejected |
| `0.1.4` | PASS | blue-square corruption | rejected |
| `1.0.3` | PASS | PASS_VISUAL | approved |
| `1.0.4` | PASS | PASS_VISUAL | approved |
| `1.1.1` | FAIL_VERIFY | not exercised | rejected |
| `1.1.4` | PASS | PASS_VISUAL | approved |

## Combined result

```text
24 stock CUs + 5 approved WGPs × 2 CUs = 34/40 CUs
```

The five-WGP set passed the heavier combined compute verification and a combined
real-desktop visual check.

The useful lesson is not "34 is safe". The useful lesson is that failures had
different signatures: one factory-disabled WGP produced incorrect compute, while
two others passed compute but corrupted the visible desktop. That is why the
workflow has independent compute and visual gates.
