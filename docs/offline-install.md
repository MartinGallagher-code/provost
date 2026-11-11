# Installing provost with no network

For an air-gapped host with no PyPI: every provost release from 2.6.0 on has
an **offline bundle** attached to its
[GitHub release](https://github.com/MartinGallagher-code/provost/releases),
`provost-X.Y.Z-offline.tar.gz`. It holds everything pip needs to install
provost, a bill of materials, checksums and signatures. Check it on the
connected side, carry it across, check it again, install.

## What is in it

| File | What it is |
|---|---|
| `provost-X.Y.Z-py3-none-any.whl` | the wheel, byte for byte the one on PyPI |
| `provost-X.Y.Z.tar.gz` | the source distribution, the one on PyPI |
| `provost-X.Y.Z.cdx.json` | the SBOM: CycloneDX 1.5 JSON |
| `INSTALL.md` | this page |
| `SHA256SUMS` | SHA-256 of the four files above |
| `*.sigstore.json` | a Sigstore bundle for each file: its signature, the signing certificate and the transparency-log entry |

The wheel is pure Python (`py3-none-any`) and provost has **no Python
dependencies**, so one wheel installs on any platform with Python 3.8 or
newer. The SBOM lists each package file with its SHA-256 and names the system
tools provost runs, which the host must already have:

| Tool | Needed | For |
|---|---|---|
| bash | yes | provost and its engines are Bash |
| git | yes | every store is a git repository |
| awk (mawk or gawk) | yes | the extract and analyze engines |
| python3, 3.8 or newer | yes | the pip launcher, `--model`, `--llm` |
| coreutils, sed, grep, findutils | yes | the engines' text handling |
| util-linux `script`, less | no | capture under a pseudo-terminal; the pager |

`provost[lm]` (the tiny language model for `--model`, 85 MB, needs numpy) is
**not** in the bundle. Without it `--model` uses the decision trees in the
wheel.

## 1. On the connected side: verify the signatures

Every file was signed by provost's release workflow on GitHub Actions, with no
key to leak: [Sigstore](https://www.sigstore.dev) binds the signature to the
workflow's identity (`MartinGallagher-code/provost`, workflow "Release to
PyPI") and records it in a public transparency log.

```bash
python3 -m pip install sigstore
python3 -m sigstore verify github \
    --repository MartinGallagher-code/provost --name "Release to PyPI" \
    provost-X.Y.Z-offline.tar.gz
```

`OK: provost-X.Y.Z-offline.tar.gz` means it is what the workflow built. To
verify the files inside one by one, unpack it and name them:

```bash
tar xzf provost-X.Y.Z-offline.tar.gz
cd provost-X.Y.Z-offline
python3 -m sigstore verify github \
    --repository MartinGallagher-code/provost --name "Release to PyPI" \
    SHA256SUMS provost-X.Y.Z-py3-none-any.whl provost-X.Y.Z.tar.gz \
    provost-X.Y.Z.cdx.json INSTALL.md
```

PyPI holds its own attestations for the wheel and sdist (PEP 740, from the same
workflow, through Trusted Publishing). Since the bundle's wheel is the PyPI
wheel, its SHA-256 matches the one PyPI shows on the release's "Download
files" page.

## 2. On the high side: check the checksums

Copy the tarball (or the unpacked directory) across. Then:

```bash
tar xzf provost-X.Y.Z-offline.tar.gz
cd provost-X.Y.Z-offline
sha256sum -c SHA256SUMS
```

Every line must say `OK`. `SHA256SUMS` is the file whose signature you checked
in step 1, so this ties each file to that signature. (If the high side has
sigstore installed, `sigstore verify github --offline ...` checks the
signatures there too, with no network.)

## 3. Install

```bash
python3 -m venv /opt/provost
/opt/provost/bin/pip install --no-index --find-links . provost
/opt/provost/bin/provost --version
/opt/provost/bin/provost doctor
```

`--no-index` stops pip from looking for PyPI at all; `--find-links .` points it
at the bundle. Put `/opt/provost/bin` on `PATH` (or link
`/opt/provost/bin/provost` into `/usr/local/bin`). `pip install --user` works
the same way.

## How it is built and tested

`.github/workflows/release.yml` builds the bundle after the PyPI upload, from
the same wheel and sdist (`tools/offline_bundle.py`), signs every file, checks
the SBOM against the CycloneDX 1.5 schema, installs it with networking off on
`python:3.8-slim` and RHEL 9 UBI, and attaches it to the GitHub release for
`vX.Y.Z` (creating that release when the workflow was run by hand). Every pull
request does the same up to the install test (`.github/workflows/ci.yml`,
`offline bundle` job), signing and verifying one file.
