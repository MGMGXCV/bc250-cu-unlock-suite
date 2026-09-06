# Acknowledgements and AI assistance

BC-250 CU Unlock Suite is a community-oriented wrapper and validation workflow built on
research and tooling from the wider BC-250/Linux ecosystem. It does **not** claim
credit for the underlying BC-250 CU unlock discoveries.

## Human testing and project direction

The workflow was iterated against a real BC-250, including irregular factory WGP
mapping, per-WGP compute tests, real-desktop visual validation, combined 34-CU
testing, game testing, a 30-minute soak test, and reboot persistence validation.
Hardware observations and the decision to accept/reject WGPs were made by the
human tester/operator.

## AI assistance disclosure

Research synthesis, test-strategy design, code drafting/refactoring,
documentation, GUI drafting, and packaging for this project were developed with
assistance from **OpenAI ChatGPT (GPT-5.6 Sol)**.

AI assistance does not constitute hardware certification. Generated code and
technical claims should be reviewed, tested on the target system, and corrected
when evidence disagrees with them. During development several experimental
automatic graphics/CRC approaches were rejected precisely because hardware tests
showed they could produce misleading results.

OpenAI does not sponsor, endorse, certify, or maintain this project.

## Upstream credit

Primary technical credit belongs to the upstream researchers and tool authors
listed in [docs/REFERENCES.md](docs/REFERENCES.md) and
[THIRD_PARTY.md](THIRD_PARTY.md), especially:

- **duggasco and contributors** — BC-250 40-CU research, dual-register analysis,
  selective WGP/CU work and Vulkan compute verifier.
- **WinnieLV and contributors** — BC-250 CU/WGP live manager, UMR integration,
  status dashboard and boot-table persistence workflow.
- **AMD/UMR contributors** — userspace AMDGPU register debugging tooling used by
  the live manager.
- The broader BC-250 Linux community whose public documentation and test reports
  informed compatibility and safety decisions.
