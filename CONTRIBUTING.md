# Contributing

Contributions are welcome, especially results from additional BC-250 boards.

## Before opening a result issue

Run:

```bash
sudo ./bc250-unlock report
```

Attach the generated Markdown report and describe:

- whether the factory topology is regular or irregular;
- which WGP produced the symptom;
- whether the symptom was compute failure, kernel fault, freeze, or visible
  corruption;
- cooling, clocks/voltage changes, and whether those settings were returned to a
  known-stable baseline during diagnosis.

## Code changes

Keep the safety properties intact:

- discovery must use the board-local boot topology;
- risky writes need a synced pending marker;
- responsive tests must restore stock before classification;
- visible corruption must be able to override synthetic PASS;
- persistence must never be enabled automatically by a discovery workflow;
- do not silently import another board's WGP profile.

Run before submitting:

```bash
bash -n bc250-unlock setup.sh scripts/*.sh
python3 -m py_compile scripts/bc250-graphics-verify.py gui/bc250_gui.py
python3 gui/bc250_gui.py --self-test
node --check gui/app.js
```

## Graphical-mode changes

Keep the GUI as a thin guide over the canonical CLI. Do not add direct UMR/SMU/register writes to browser handlers. New GUI actions must be fixed IDs in the backend whitelist and must launch an existing audited CLI command in a visible terminal.

## Attribution and source hygiene

When a change is based on a public technical source, add or update the relevant entry in `docs/REFERENCES.md`. If code is copied or substantially adapted from another project, preserve its license/copyright obligations and update `THIRD_PARTY.md` before opening the contribution. Do not vendor unlicensed third-party source into release archives.
