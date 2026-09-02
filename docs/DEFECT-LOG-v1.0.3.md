# CCTV AI/NVR v1.0.3+ Defect Log — Initial Remediation Cycle

**Status:** OPEN / BLOCKED — this is not a production-validation report.

**Date:** 2026-09-03 (Asia/Makassar)
**Baseline:** `cctv-ai-server-1.0.2-linux-x86_64.zip`
**Baseline SHA-256:** `bee2b763f9bd01d487d51db4261b0d24b636885f82990814912aacff7ab99cbe`
**Evidence:** [`test-results/00-baseline-v1.0.2.txt`](../test-results/00-baseline-v1.0.2.txt)

## Rules applied

- The v1.0.2 ZIP is immutable and remains unchanged.
- A defect is not closed from source inspection or a successful command alone.
- No PASS is recorded for an unexecuted runtime acceptance test.
- No release version, binary, checksum, or production verdict is fabricated.

## Critical defects from the remediation request

### C1 — AI tensor layout

- **Severity:** CRITICAL
- **Status:** OPEN — NOT REPRODUCED / NOT FIXED
- **Required acceptance:** A known-good human frame must go through the real application preprocessing and produce non-zero valid person detections; the regression must fail if HWC data is interpreted as NCHW.
- **Root cause:** Not determinable from the connected checkout. The ZIP contains only a stripped release binary and no source, tensor fixture, model, reference preprocessing tool, or raw baseline frame/result. The supplied v1.0.2 documentation claims an AI load test but reports `detections=0` in its benchmark; it does not provide the requested HWC-versus-NCHW reproduction evidence.
- **Attempted verification:** Static binary inspection found ONNX Runtime and tensor-related strings, but the binary could not start on the audit host. No inference result is being treated as evidence.
- **Fix:** BLOCKED until the Rust workspace and the exact regression fixture/model are available.
- **Regression test:** BLOCKED. Must include shape `[1,3,H,W]`, length `1*3*H*W`, channel-plane sentinel values, numerical reference comparison, and known-good human-frame detection.

### C2 — ONNX Runtime failure / incompatible dependency

- **Severity:** CRITICAL
- **Status:** OPEN — NOT REPRODUCED / NOT FIXED
- **Required acceptance:** Missing, incompatible, unloadable, or failed ORT initialization must degrade AI without killing the NVR; `model validate` must return a human-readable non-zero result and never panic/abort.
- **Root cause:** Not determinable from the connected checkout. Source-level FFI/error paths and the exact incompatible ORT library are unavailable. Static strings show ORT 2.0.0-rc.13 integration and an `abort` path, but this is not sufficient to prove runtime behavior.
- **Attempted verification:** The release binary was invoked with `--help`; the dynamic loader failed before application code ran because the host provides GLIBC 2.36 while the binary requires GLIBC 2.39. Therefore ORT failure tests could not be executed.
- **Fix:** BLOCKED until source and a compatible clean test host/runtime fixture are available. The fix must make ORT dependency resolution deterministic and distinguish expected runtime failures from programmer invariants.
- **Regression test:** BLOCKED. Must cover missing library, incompatible library, invalid model, load failure, inference failure, recording continuity, camera continuity, API health, and bounded recovery.

### C3 — Camera ID persistence/collision

- **Severity:** CRITICAL
- **Status:** OPEN — NOT REPRODUCED / NOT FIXED
- **Required acceptance:** Camera IDs must be database-backed, unique, persistent across restart/upgrade/rollback, transactional, and incapable of overwriting an existing camera.
- **Root cause:** Not determinable from the connected checkout. No database schema, migration, camera handlers, or source tests are available. The archive documentation asserts database tooling but contains no camera-ID regression matrix or raw API evidence.
- **Attempted verification:** Runtime API test could not start because the binary fails at the dynamic loader stage. No camera behavior is being inferred from documentation.
- **Fix:** BLOCKED until the Rust workspace and a runnable environment are available.
- **Regression test:** BLOCKED. Must cover restart, upgrade, rollback, concurrent creation, delete-then-create, migration, uniqueness, and safe collision failure.

## Additional defects and blockers found

### D1 — Documented Ubuntu 22.04 compatibility is not established by the artifact

- **Severity:** P1 (deployment compatibility)
- **Status:** OPEN
- **Evidence:** `readelf -V` reports a highest required GLIBC symbol of `GLIBC_2.39`. Ubuntu 22.04 ships an older glibc baseline than that. The installer checks OS and architecture but does not perform a libc compatibility preflight before installation. The release documentation lists Ubuntu 22.04 as supported.
- **Observed on:** Debian 12 / GLIBC 2.36. `/tmp/cctv-server-baseline --help` exits `1` with `GLIBC_2.39 not found` before the application starts.
- **Impact:** The artifact cannot be runtime-validated here and is very likely not executable on the documented Ubuntu 22.04 target. This conflicts with the self-contained installation claim.
- **Required fix:** Rebuild against the documented minimum libc baseline or ship a deterministic compatible runtime/container strategy, and add an installer preflight with an actionable error. Verify on clean Ubuntu 22.04 and 24.04 hosts.

### B1 — Source repository unavailable

- **Severity:** BLOCKER for remediation
- **Status:** OPEN
- **Evidence:** `git ls-files`, GitHub API repository contents, and the recursive Git tree all contain only `cctv-ai-server-1.0.2-linux-x86_64.zip`. There is no `src/`, `crates/`, `Cargo.toml`, `Cargo.lock`, test fixture, build script, or model file.
- **Impact:** C1/C2/C3 cannot be root-caused or fixed, no Rust tests can be added, and a new release cannot be built without reverse-engineering or patching a binary. Neither is an acceptable production remediation path.
- **Required action:** Provide/publish the Rust source workspace and the build/release inputs in the connected GitHub repository, or attach them to this branch.

### B2 — Required clean validation hosts unavailable

- **Severity:** BLOCKER for final gate
- **Status:** OPEN
- **Evidence:** The current sandbox is Debian 12, not clean Ubuntu 24.04. No Docker, Podman, LXC, QEMU, or systemd-nspawn runtime is available for creating the required two independent clean Ubuntu hosts.
- **Impact:** Clean Host A, Clean Host B, Ubuntu 22.04 compatibility, browser workflow, real RTSP, reboot, systemd, upgrade/rollback, uninstall, and purge cannot honestly be marked PASS from this environment.
- **Required action:** Provide two disposable clean Ubuntu x86_64 hosts/VMs (and real camera hardware or explicitly documented RTSP publisher limitation).

## Initial status matrix

| Area | Status | Reason |
|---|---|---|
| Immutable baseline | PASS | ZIP hash unchanged and recorded |
| ZIP integrity | PASS | `unzip -t` and 22/22 inner SHA-256 checksums pass |
| Source audit | BLOCKED | Source absent from repository |
| C1 tensor correctness | NOT TESTED | Binary cannot run; fixture/source absent |
| C2 ORT resilience | NOT TESTED | Binary cannot run; ORT fixture/source absent |
| C3 camera persistence | NOT TESTED | Binary cannot run; DB/source absent |
| Install on clean Ubuntu 24.04 Host A | BLOCKED | No clean Ubuntu host available |
| Install on clean Ubuntu 24.04 Host B | BLOCKED | No second clean Ubuntu host available |
| Install on clean Ubuntu 22.04 | BLOCKED | No clean host; GLIBC requirement is already concerning |
| Real-user browser workflow | BLOCKED | Service cannot start in current environment |
| Real camera / RTSP | NOT TESTED | No hardware or clean runnable host |
| Upgrade / rollback | NOT TESTED | Source, runnable host, and second release absent |
| Uninstall / purge | NOT TESTED | No installation was performed |
| Production score | NOT SCORED | Core gates are unverified; automatic verdict is NOT PRODUCTION READY |

## Current verdict

**NOT PRODUCTION READY.**

C1, C2, and C3 remain open. D1, B1, and B2 prevent a valid remediation/build/clean-host cycle. The original ZIP is preserved; no unsupported PASS, score, or final release has been created.
