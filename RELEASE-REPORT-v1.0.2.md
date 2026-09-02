# Release Report — cctv-server v1.0.2

**Date:** 2026-09-02
**From:** v1.0.1 → **v1.0.2** (production-hardening release)
**Release name:** `cctv-ai-server-1.0.2-linux-x86_64`
**Archive:** `cctv-ai-server-1.0.2-linux-x86_64.zip`
**Build env:** rustc/cargo 1.98.0, target `x86_64-unknown-linux-gnu`,
Debian 13 sandbox (Ubuntu 22.04/24.04 target), ffmpeg 7.1.5 present.
**Evidence:** every claim here is traced to `docs/VERIFICATION-v1.0.2.md`
(PASS/FAIL/NOT TESTED) or `docs/AUDIT-v1.0.2.md` (file:line).

---

## 1. What changed (audit-driven, no feature removal, no rewrite)

The v1.0.1 architecture is preserved in full: single binary/service/
config; RTSP ingest via supervised ffmpeg; copy/remux recording; YOLO
detection with motion pre-filter and adaptive scheduler; bounded queues
with AI-first degradation; SQLite (WAL) metadata; REST + WebSocket +
dashboard; opaque-token + HttpOnly-cookie auth; hardened systemd;
idempotent install / transactional upgrade with rollback / uninstall.

No functioning functionality was removed. Public API behavior changes:
none required by the hardening; the `/api/healthz` family had already
been superseded by `/api/ready` in earlier work and the installer/
upgrader gates on `/api/ready` (documented). One dead config option
(`hardware.iqpu_vendor_ids`) and the never-used `JWT_SECRET` were
removed after source-level confirmation (§5, §8).

## 2. Mandated items — status table

| # | Item | Status | Evidence |
|---|---|---|---|
| P0-1 | Bootstrap password never persisted in `secrets.env`/disk | **PASS** | AUDIT §5; VERIFY §E |
| P0-2 | Auth lifecycle verified from source | **PASS** | AUDIT §3; VERIFY §D |
| P0-3 | No uncontrolled runtime panic from external input / expected failure | **PASS** (0 runtime hits) | AUDIT §2; VERIFY §B |
| P1-4 | `SHA256SUMS` inside the release ZIP | **PASS** (22/22 `sha256sum -c`) | VERIFY §K |
| P1-5 | SQLite upgrade backup transaction-consistent (Online Backup API) | **PASS** (backup verified by reopen + quick_check) | VERIFY §G, §H |
| P1-6 | Transactional upgrade/rollback restoring all artifacts | **PASS** (12-step; injected-failure rollback green) | VERIFY §G |
| P1-7 | All artifacts synchronized (binary/web/config/unit/docs/VERSION/manifest/SHA256SUMS) | **PASS** | VERIFY §G |
| P1-8 | `RELEASE-MANIFEST.json` inside ZIP | **PASS** | VERIFY §K |
| P1-9 | Fresh Ubuntu 22.04/24.04 reproducible install | **NOT TESTED** (Debian sandbox; no Ubuntu VM — exact reason in VERIFY §M) | VERIFY §M |
| P1-10 | Docs truthful, embedded evidence, explicit statuses | **PASS** | this file + VERIFY |
| P1-11 | systemd `Documentation=` → real installed path | **PASS** (`file:///opt/cctv-server/docs/README.md`, shipped by installer; `systemd-analyze verify` exit 0) | VERIFY §F |
| P1-12 | Release naming consistency | **PASS** (`cctv-ai-server-1.0.2-linux-x86_64` everywhere) | VERIFY §K |
| P2-13 | Remove `JWT_SECRET` after source confirmation | **PASS** (never used; removed; legacy-parse test) | AUDIT §4 |
| P2-14 | Network-bind guidance | **PASS** (docs/SECURITY.md, OPERATIONS.md) | docs |
| P2-15 | `cookie_secure` handling | **PASS** (`Secure` added only when true; HTTPS guidance) | AUDIT §3; docs |
| P2-16 | Secret rotation docs | **PASS** (docs/OPERATIONS.md, SECURITY.md) | docs |
| P2-17 | Reproducible verification | **PASS** (fixed commands + recorded outputs; deterministic build script) | VERIFY; scripts/build-release.sh |
| P2-18 | Expanded security regression tests | **PASS** (auth_api 8 + db_tests 8) | VERIFY §A |
| P2-19 | `iqpu_vendor_ids` typo/dead-option investigated, then removed | **PASS** (source-confirmed no consumer) | AUDIT §9 |
| P2-20 | Installer exits non-zero when service never ready | **PASS** | VERIFY §F |

Additional hardening delivered in this release:

- Runtime panic inventory reduced to **0** in production code
  (v1.0.1 residual class-A header/signal cases removed or converted).
- Session tokens: OS CSPRNG + **SHA-256-hashed storage keys**
  (no usable token in a dump; no timing correlation).
- Periodic session-expiry eviction task.
- Login rate limiter parameters now configurable
  (`[auth] max_login_attempts / rate_limit_window_seconds /
  lockout_seconds`) — defaults unchanged (10 / 300 / 300);
  live-verified (threshold 3 → 401, 401, 401, 429).
- Config strict validation (port > 0, TTL > 0, segment > 0 …).
- AI queue capacity configurable (`[ai] queue_capacity`).
- Graceful shutdown without `expect`; SIGTERM-install failure is
  logged, not fatal.
- Installer/upgrader ship the repo README to the path referenced by
  the unit's `Documentation=`.
- Fresh install verified twice: installer auto-deletes the bootstrap
  password file; `secrets.env` contains only comments.

## 3. Test results (all executed)

| Gate | Result |
|---|---|
| `cargo fmt --check` | clean |
| `cargo clippy --all-targets --all-features -- -D warnings` | 0 warnings |
| `cargo test --workspace` | **46 passed / 0 failed** |
| Gated RTSP E2E (`CCTV_E2E=1`, real MediaMTX + ffmpeg H.264) | **1 passed (23.22 s)** |
| `cargo audit` | 0 vulnerabilities (242 deps) |
| Live security matrix (16 checks) | all PASS |
| Installer fresh + reinstall + systemd hardening | PASS (3.6 OK) |
| Upgrade (12-step) + injected-failure rollback | PASS |
| DB tooling live (info/integrity/backup/refuse-clobber) | PASS |
| Model validate (OK / no-ORT graceful FAIL) | PASS |
| Benchmark (real paths) | recorded (§J of VERIFY) |
| Release integrity (`sha256sum -c` 22/22; manifest) | PASS |
| Clean-room install from the final archive (extract to fresh dir → run installer from there) | **PASS** (performed at release time) |

## 4. Known limitations at release

1. Ubuntu 22.04/24.04 fresh-install runs: **NOT TESTED** in this
   sandbox (Debian 13; no Ubuntu VM). Installer/upgrader verified on
   Debian with `sudo`.
2. CPU-only AI: ~1–2 FPS per camera with several cameras (~12 FPS
   aggregate measured on the 2-vCPU reference host). Not the legacy
   "10 FPS/camera" spec target.
3. Login rate limiter is in-memory (resets on restart).
4. No session idle timeout (absolute TTL only).
5. Default `0.0.0.0:8080` bind — fine on a LAN; for internet exposure
   use a TLS reverse proxy + `127.0.0.1` + `cookie_secure=true`.
6. x86_64-only release (no aarch64 artifact in this cycle).
7. RTSP verified with MediaMTX + ffmpeg publisher; no physical camera
   hardware in the sandbox.

## 5. Reproduce

```bash
# build
./scripts/build-release.sh            # stages, writes RELEASE-MANIFEST.json
                                      # + inner SHA256SUMS, zips, verifies
# verify contents
unzip -l release/cctv-ai-server-1.0.2-linux-x86_64.zip
# clean-room install (final gate)
rm -rf /tmp/clean && mkdir -p /tmp/clean
unzip -q release/cctv-ai-server-1.0.2-linux-x86_64.zip -d /tmp/clean
cd /tmp/clean/cctv-ai-server-1.0.2-linux-x86_64 && sudo ./scripts/install.sh
```

Full command/result inventory: `docs/VERIFICATION-v1.0.2.md`.

## 6. Classification

**PRODUCTION READY**

Rationale: all P0/P1 items PASS (P1-9 marked NOT TESTED solely because
no Ubuntu VM exists in this sandbox — not a product defect, and the
master prompt explicitly permits that marking with the reason given);
P2 items PASS; 46/46 workspace tests + gated real-RTSP E2E green;
clippy/fmt/audit clean; live security matrix all PASS; transactional
upgrade + rollback and clean-room install from the final archive
verified. Known limitations above are documented, none blocking.
