# Repository Structure and Remediation Layout

**Date:** 2026-09-03 (Asia/Makassar)
**Current branch:** `arena/01a06385-cctv`
**Status:** baseline/evidence organization complete; source remediation blocked

## Design rules

1. The v1.0.2 ZIP is a release baseline, not a source tree.
2. The ZIP remains at the repository root and is immutable.
3. Evidence is kept separate from product artifacts under `test-results/`.
4. Audit and defect documentation is kept under `docs/`.
5. No placeholder Rust files or invented source are added.
6. A future rebuilt release must use a new version and a new artifact; it must
   never overwrite v1.0.2.

## Current layout

```text
.
├── cctv-ai-server-1.0.2-linux-x86_64.zip  # immutable release baseline
├── README.md                              # repository entry point/status
├── docs/
│   ├── DEFECT-LOG-v1.0.3.md               # C1/C2/C3/D1 and blockers
│   └── REPOSITORY-STRUCTURE.md            # this file
└── test-results/
    ├── 00-baseline-v1.0.2.txt             # prior baseline record
    ├── 00-baseline-zip.txt                # hash and archive test
    ├── 01-zip-extraction.txt              # isolated extraction
    ├── 02-source-inventory.txt            # ZIP/workspace inventory
    ├── 03-branch-baseline.txt             # branch/status evidence
    ├── 04-source-provenance.txt           # Git/GitHub provenance search
    ├── c1-before-fix.txt                   # C1 attempt, blocked
    ├── c2-before-fix.txt                   # C2 attempt, blocked
    ├── c3-before-fix.txt                   # C3 attempt, blocked
    └── d1-before-fix.txt                   # GLIBC compatibility failure
```

## Target layout after source is supplied

The following is the intended structure for the next source-based remediation
cycle. It is deliberately documented rather than fabricated as empty source:

```text
.
├── Cargo.toml                              # workspace manifest
├── Cargo.lock                              # locked dependency graph
├── crates/
│   ├── cctv-core/                          # config, DB, identity, security
│   ├── cctv-ai/                            # preprocessing, ORT, postprocess
│   ├── cctv-camera/                        # RTSP ingest and camera lifecycle
│   ├── cctv-video/                         # FFmpeg process supervision
│   ├── cctv-api/                           # REST, WebSocket, auth, media
│   ├── cctv-recording/                     # segment/index handling
│   ├── cctv-storage/                       # retention and disk pressure
│   ├── cctv-events/                        # event processing
│   └── cctv-tracking/                      # detection tracking
├── src/                                    # cctv-server binary/CLI
├── tests/
│   ├── fixtures/                           # known-good human frame/model refs
│   ├── ai/                                 # tensor/reference inference tests
│   ├── camera/                             # identity/restart/concurrency tests
│   ├── runtime/                            # ORT degradation/failure tests
│   └── release/                            # package/installer regression tests
├── migrations/                             # transactional DB migrations
├── scripts/                                # reproducible build/release helpers
├── config/                                 # example configuration
├── systemd/                                # service unit
├── web/                                    # dashboard assets
├── models/                                 # documentation/checksums, not secrets
├── docs/                                   # design, security, operations, reports
├── test-results/                           # immutable command/test evidence
└── release/                                # generated versioned artifacts
```

The target layout must only be materialized once the corresponding source and
build inputs are actually available. A directory skeleton without source does
not constitute a reconstructed workspace and must not be used to create a
release.

## Branch note

The requested new branch name cannot be created in this Arena session because
the session is fixed to `arena/01a06385-cctv`. The structural documentation is
therefore committed on that fixed branch; no other branch was created or
pushed.

## Gate to proceed

Before implementing C1–C3 or D1, verify that all of the following are present:

- Rust workspace and exact source provenance
- locked dependencies and release build script
- C1 model and known-good human-frame fixture
- deterministic ORT dependency strategy
- clean Ubuntu 24.04 test hosts (two independent hosts)
- access to real RTSP hardware or an explicitly documented realistic publisher
