# Publishing on GitHub

Recommended repository name:

```text
bc250-cu-unlock-suite
```

Suggested description:

> Experimental BC-250 CU/WGP testing and selective unlocking with compute isolation, human visual validation, bilingual GUI, SteamOS support and reversible boot persistence.

Suggested topics:

```text
bc250 amd amdgpu rdna2 linux cachyos archlinux steamos gpu reverse-engineering
```

## First push

After extracting the source archive:

```bash
cd bc250-cu-unlock-suite-v0.4.0
git init
git add .
git commit -m "BC-250 CU Unlock Suite v0.4.0"
git branch -M main
```

Create the GitHub repository and push:

```bash
git remote add origin git@github.com:YOURNAME/bc250-cu-unlock-suite.git
git push -u origin main
```

The repository already contains README files, `.gitignore`, MIT `LICENSE`, issue
templates and GitHub Actions. Do not generate conflicting versions when creating
the remote repository unless you plan to replace them.

## Publishing a release

The repository includes `.github/workflows/release.yml`. Pushing a version tag
matching the `VERSION` file automatically:

1. reruns syntax/self-tests;
2. creates clean `.tar.gz` and `.zip` archives;
3. creates `RELEASE-CHECKSUMS.sha256`;
4. publishes a GitHub Release using `RELEASE_NOTES.md`.

For v0.4.0:

```bash
git tag -a v0.4.0 -m "BC-250 CU Unlock Suite v0.4.0"
git push origin v0.4.0
```

The tag must match `VERSION` or the release workflow intentionally fails.

## License recommendation

Keep the existing **MIT** license unless you intentionally want stronger
copyleft. MIT is short, permissive and widely recognized, and includes an
AS-IS/no-warranty clause. `docs/LICENSING.md` explains MIT vs Apache-2.0 vs
GPL-3.0 and the third-party boundary.

Do not vendor `bc250-cu-live-manager` into a release archive unless its upstream
licensing explicitly permits redistribution. `duggasco/bc250-40cu-unlock`
advertises GPL-2.0 and remains a separately fetched upstream dependency.

## Credits / references before publishing

Keep these files in the public repository:

- `SAFETY.md`
- `ACKNOWLEDGEMENTS.md`
- `THIRD_PARTY.md`
- `docs/REFERENCES.md`
- `docs/LICENSING.md`

They document responsibility, upstream technical credit, third-party licensing
and the OpenAI ChatGPT assistance disclosure.

## GUI screenshots

The optional GUI is browser-based and local-only. If you add screenshots, capture
only the interface itself; avoid terminal windows containing usernames,
home-directory paths, IP addresses or other machine-specific information.

## Release checklist

```bash
bash -n bc250-unlock bc250-lab setup.sh scripts/*.sh
python3 -m py_compile scripts/bc250-graphics-verify.py gui/bc250_gui.py
python3 gui/bc250_gui.py --self-test
node --check gui/app.js
sha256sum -c CHECKSUMS.sha256
```

Also test at least:

- `./bc250-unlock --help` and platform detection;
- GUI launch as a non-root desktop user;
- one terminal launch from the GUI;
- application-menu shortcut install/remove;
- `doctor` and `status` on a real BC-250 before tagging a release.
