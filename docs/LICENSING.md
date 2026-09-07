# Licensing notes

This is practical project-maintenance guidance, **not legal advice**.

## Recommended license: MIT

BC-250 CU Unlock Suite currently uses the **MIT License**, and that is the recommended
choice for this repository in its present architecture.

Why MIT fits well here:

- it is short and widely recognized;
- it permits use, modification and redistribution with minimal conditions;
- it includes an explicit `AS IS` / no-warranty disclaimer;
- this repository is primarily original wrapper, validation, GUI and
  documentation code;
- key upstream projects are fetched separately rather than vendored/relicensed.

Official MIT text/reference:
https://opensource.org/license/mit

GitHub recommends including an explicit license if a repository is intended to
be open source:
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository

## Alternatives you could choose

### Apache-2.0

Choose Apache-2.0 if you want a permissive license like MIT but also prefer a
more explicit patent-license framework. It is longer and adds more compliance
text.

### GPL-3.0

Choose GPL-3.0 if your priority is requiring redistributed derivative versions
of **this project's code** to remain under the GPL. This is a stronger copyleft
choice and changes how downstream redistribution works.

Neither alternative is required merely because this toolkit executes separately
fetched GPL software. If you later copy GPL code into this repository, revisit
the licensing structure before publishing that version.

## Third-party boundary

The project's `LICENSE` covers files authored as part of BC-250 CU Unlock Suite. It does
not relicense code downloaded into `./upstream/`.

Important current cases:

- `duggasco/bc250-40cu-unlock` advertises GPL-2.0; its verifier remains GPL-2.0.
- `WinnieLV/bc250-cu-live-manager` did not advertise an explicit license when
  this release was reviewed. Do not bundle/redistribute its source in BC-250 CU Unlock Suite
  releases unless the upstream licensing situation permits it.

See [../THIRD_PARTY.md](../THIRD_PARTY.md) and
[REFERENCES.md](REFERENCES.md).
