# CCTV AI/NVR Repository

Repository status: **baseline and remediation evidence only**.

## Immutable release baseline

The original release is preserved at the repository root and must not be
modified or replaced:

```text
cctv-ai-server-1.0.2-linux-x86_64.zip
SHA256: bee2b763f9bd01d487d51db4261b0d24b636885f82990814912aacff7ab99cbe
```

The archive has been extracted for inspection into an isolated temporary
workspace. Extraction and its internal `SHA256SUMS` verification passed.

## Current repository layout

```text
.
├── cctv-ai-server-1.0.2-linux-x86_64.zip   # immutable v1.0.2 artifact
├── README.md                               # repository status and entry point
├── docs/
│   ├── DEFECT-LOG-v1.0.3.md                # open defects and blockers
│   └── REPOSITORY-STRUCTURE.md             # actual and target layout
└── test-results/                            # command/output evidence
    ├── 00-baseline-v1.0.2.txt
    ├── 00-baseline-zip.txt
    ├── 01-zip-extraction.txt
    ├── 02-source-inventory.txt
    ├── 03-branch-baseline.txt
    ├── 04-source-provenance.txt
    ├── c1-before-fix.txt
    ├── c2-before-fix.txt
    ├── c3-before-fix.txt
    └── d1-before-fix.txt
```

Files in `test-results/` are evidence, not claims that blocked tests passed.

## Source status

No Rust workspace is present in the ZIP, the connected GitHub repository, or
the searched workspace. In particular, there is no `Cargo.toml`,
`Cargo.lock`, `src/`, `crates/`, Rust test fixture, build script, migration,
or ONNX model. Binary patching is intentionally not used as a substitute for
source remediation.

The current release therefore cannot be rebuilt into v1.0.3 from this
checkout. C1 (AI tensor layout), C2 (ORT failure handling), C3 (camera ID
persistence), and D1 (GLIBC compatibility) remain open. See
[`docs/DEFECT-LOG-v1.0.3.md`](docs/DEFECT-LOG-v1.0.3.md).

## Next required input

To continue with a real source-based remediation, add the Rust workspace and
its provenance/build inputs to this repository or provide them in the working
workspace. The source must be accompanied by the exact model/test fixture
needed for the C1 regression and a reproducible release build environment.

Do not label a release Production Ready until the required clean-host and
real-user tests have been executed and all critical/P1 defects are closed.
