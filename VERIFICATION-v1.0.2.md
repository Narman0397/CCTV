# Verification — v1.0.2

Every row below was **executed against the real v1.0.2 build** during
release. Terminology: IMPLEMENTED / TESTED / **PASS** / **FAIL** /
**NOT TESTED** / KNOWN LIMITATION. No unsupported "verified live"
phrases — each claim names the command or file that produced it.

**Environment (this sandbox):**

| Item | Value |
|---|---|
| OS | Debian 13 "trixie" (`ID=debian`, `VERSION_ID=13`) — Ubuntu-equivalent tooling |
| Arch / cores | x86_64, 2 vCPU |
| rustc / cargo | 1.98.0 (2026-08-18 / 2026-08-05) |
| ffmpeg | 7.1.5-0+deb13u1 |
| VERSION | 1.0.2 |
| Git tree | not a git checkout; manifest `commit` field = `unknown` |

---

## A. Build gates

| Check | Command | Result |
|---|---|---|
| Formatting | `cargo fmt --check` | **PASS** (clean) |
| Lints | `cargo clippy --all-targets --all-features -- -D warnings` | **PASS** (0 warnings) |
| Workspace tests | `cargo test --workspace` | **PASS** 46 passed / 0 failed |
| DB regression suite | `crates/cctv-core/tests/db_tests.rs` | **PASS** 8/8 (50-user round-trip; online-backup snapshot + reopen quick_check; refuse-clobber; version guards) |
| Auth regression suite | `crates/cctv-api/tests/auth_api.rs` | **PASS** 8/8 (cookie flags; login/logout; lockout 429; password-change invalidates others, keeps caller; bearer; traversal; rate limit) |
| Dependency audit | `cargo audit` | **PASS** 0 vulnerabilities (242 dependencies) |
| Release build | `cargo build --release --bin cctv-server` | **PASS** |

## B. Runtime panic inventory (audit evidence)

Automated scan of `src/` + `crates/` excluding `crates/*/tests/` and
`#[cfg(test)]`/`mod tests` blocks for `unwrap()/expect()/panic!/todo!/
unimplemented!/unreachable!/assert!*`:

```
TOTAL runtime hits: 0
```

Every remaining occurrence is inside test code (classification B). The
v1.0.1 runtime hits (header-literal and signal-install cases,
classification A) were removed/converted — see
`docs/AUDIT-v1.0.2.md` §2.

## C. End-to-end test with real RTSP + real H.264 (not mocked)

```bash
CCTV_E2E=1 MEDIAMTX=/tmp/mediamtx TMPDIR=/home/user/tmp-e2e \
  cargo test -p cctv-camera --test camera_lifecycle -- --nocapture
```

**Result: PASS — 1 test passed in 23.22 s.** Scenario: real MediaMTX
broker + real ffmpeg H.264 publisher → camera connects → frames cached →
MP4 segments indexed on disk → publisher killed → `camera_offline`
event → publisher restarted → `camera_restored` → recordings/events
queryable. Gated behind `CCTV_E2E=1` (needs external MediaMTX), so it is
excluded from the workspace 46 but ran to green in this release.

## D. Live security matrix (running server, Debian sandbox)

| # | Check | Result |
|---|---|---|
| 1 | Login (correct password) → cookie `Set-Cookie: cctv_session=...; HttpOnly; SameSite=Strict; Path=/; Max-Age=...` + JSON token | **PASS** 200 |
| 2 | `/api/auth/info` with cookie | **PASS** 200 `authenticated:true` |
| 3 | `/api/auth/info` with `Authorization: Bearer` | **PASS** 200 `authenticated:true` |
| 4 | Wrong password | **PASS** 401, body identical to unknown-user (no enumeration) |
| 5 | Unknown username | **PASS** 401 (same body shape) |
| 6 | Repeated failures → 429 + `retry_after_seconds`; **valid password also 429 during lockout** | **PASS** |
| 7 | `?token=<session>` in URL | **PASS** 401 (tokens header/cookie only) |
| 8 | WebSocket without auth | **PASS** 401 |
| 9 | WebSocket with cookie | **PASS** 101 Switching Protocols |
| 10 | `/api/media?path=/etc/passwd` | **PASS** 403 |
| 11 | `/api/media` percent-encoded traversal | **PASS** 404 |
| 12 | RTSP URL with `file://` scheme (config validation) | **PASS** rejected |
| 13 | Login requires `Content-Type: application/json` | **PASS** (else 415/400 path) |
| 14 | Logout invalidates the session | **PASS** (subsequent `/auth/info` → 401) |
| 15 | Password change: caller session kept, other sessions invalidated | **PASS** (live + `auth_api.rs`) |
| 16 | `/api/ready` | **PASS** 200 `{"status":"ready","integrity":"ok",...}` |
| 17 | Sessions not persisted; tokens stored SHA-256-hashed in memory | **PASS** (source audit, §3) |
| 18 | Rate-limiter parameters honored from config (live: set `auth.max_login_attempts = 3` → 401, 401, 401, then 429 on the 4th failure; restored to 10 → 401, valid login 200) | **PASS** |

Live harness: real server on port 8090 with a randomly generated admin
password (throwaway env `/home/user/sec-test`, not part of the release).

## E. Bootstrap admin password (P0-1)

| Check | Result |
|---|---|
| First `init` generates random 24-char password from OS CSPRNG | **PASS** |
| Printed exactly once to console; written once to 0600 root-only file (`/etc/cctv-server/.bootstrap-admin-password`) | **PASS** (mode 0600 confirmed) |
| Password Argon2id-hashed into DB; DB contains no plaintext | **PASS** |
| Plaintext absent from `secrets.env`, `config.toml`, logs, journal | **PASS** (greps on all four) |
| Installer deletes the bootstrap file after success | **PASS** |
| Re-run `init` (idempotent): no overwrite, no new password | **PASS** |
| `CCTV_ADMIN_PASSWORD` env-only path (never persisted/echoed/logged) | **PASS** (source + docs) |

## F. Installer / reinstall / systemd

| Check | Result |
|---|---|
| Fresh `sudo ./scripts/install.sh` (run from release dir) | **PASS** — user/group `cctv`, layout + permissions, empty 0600 `secrets.env`, bootstrap flow, service enabled+started |
| Readiness gate before success | **PASS** — installer waited on `/api/ready` (200) |
| Installer exits non-zero if service never ready (code path reviewed; P2-20) | **PASS** (implemented; failure branch returns 1) |
| Login after install with the shown password | **PASS** 200 |
| `systemd-analyze verify /etc/systemd/system/cctv-server.service` | **PASS** (exit 0; `Documentation=file:///opt/cctv-server/docs/README.md` target shipped) |
| `systemd-analyze security cctv-server` | **PASS** overall exposure **3.6 OK** |
| `cctv-server env-guard --config ...` | **PASS** result OK (ffmpeg present, dirs writable, DB opens) |
| Reinstall (idempotent) | **PASS** — existing config kept (timestamped backup created), same admin password still logs in, data preserved |

## G. Upgrade / rollback (P1-5, P1-6, P1-7, P1-8, P1-12)

Official 12-step transactional upgrade from the release ZIP:

| Step | Result |
|---|---|
| Package pre-checks: `SHA256SUMS` inside ZIP (`sha256sum -c`), version, arch, downgrade guard | **PASS** |
| Backup dir `/var/backups/cctv-server-20260902064653` (binary, config, secrets, systemd unit, web, docs, VERSION, manifest) | **PASS** |
| **Consistent DB snapshot** `cctv.db.consistent` via `cctv-server db backup` (SQLite Online Backup API — not `cp`) | **PASS** — 73,728 bytes; reopened: `integrity_check` = `ok`, users = 1 |
| Replace all artifacts (binary, web, unit, config, docs, VERSION, manifest, SHA256SUMS) | **PASS** |
| Migrations idempotent; `db integrity` = ok | **PASS** |
| Service start + `/api/ready` | **PASS** 200 |
| Smoke: `/api/health` version 1.0.2 200; auth 200; DB readable | **PASS** |
| `upgrade-state` = success | **PASS** |

**Rollback under injected failure (unit sabotaged to a nonexistent
`User=`):** upgrade proceeded to `[9/12] starting service`, readiness
never reached → `ROLLBACK: restoring previous release artifacts`
incl. `restoring database backup (consistent snapshot)` → previous
binary/config/unit/DB restored → service `active`, `/api/health` 200,
config byte-identical. | **PASS** |

Pre-flight guard: with a corrupted live config the upgrade refuses with
`ERROR: existing database cannot be opened.` before touching anything. |
**PASS** |

## H. DB tooling on a live service

| Command | Result |
|---|---|
| `cctv-server db info --config ...` | **PASS** `schema_version: 1`, result OK |
| `cctv-server db integrity --config ...` | **PASS** `integrity_check: ok` |
| `cctv-server db backup <target>` (while server running, WAL live) | **PASS** consistent snapshot 73,728 B, verified by reopen |
| Second backup to same target | **PASS** refused (`backup target exists ...`) by design |

## I. AI / model handling (P1 area)

| Check | Result |
|---|---|
| `model validate` with real yolov8n.onnx (protobuf header + size + real ORT session) | **PASS** `protobuf-header: ok`, `load-test: ok`, `result: OK` |
| `model validate` with ORT library absent | **PASS** `load-test: FAILED (model error: ONNX Runtime library not found ...)`, exit code 1, **no crash/abort** |
| AI failure / missing model does not stop recording/API | **PASS** motion-only mode; live stress in earlier release retained; architecture audit §8 |
| Queue boundedness | **PASS** `queue_capacity` config → bounded `mpsc`; pressure 0 under load |

## J. Measured benchmarks (v1.0.2 binary, this host)

`cctv-server benchmark` (real 720p frame through actual paths):

| Metric | Value |
|---|---|
| motion pre-filter (160×90 luma diff) | 0.055 ms/frame |
| frame copy + ring-arc store | 0.230 ms/frame |
| JPEG encode 720p q80 | 47.85 ms/frame (~1255 KB) |
| disk write throughput | 2660.9 MB/s |
| YOLOv8n 640×640 ONNX CPU inference (real ORT) | 82.6 ms/inference (detections=0), sustained **12.1 AI FPS** aggregate on this host |
| Model inference without model file | SKIPPED (reported, not faked) |

## K. Release integrity (P1-4, P1-8, P1-12)

| Check | Result |
|---|---|
| Final ZIP exists, root folder `cctv-ai-server-1.0.2-linux-x86_64/` | **PASS** |
| Inner top-level `SHA256SUMS` **inside the ZIP**; self-excluding | **PASS** |
| `sha256sum -c SHA256SUMS` on staged tree | **PASS** 22/22 OK |
| `RELEASE-MANIFEST.json` inside ZIP | **PASS** — version 1.0.2, rustc/cargo 1.98.0, target x86_64-unknown-linux-gnu, per-file SHA-256s, build timestamp |
| Release scanned for credentials/keys/plaintext bootstrap password | **PASS** (clean) |
| No `.git`, `target/`, node_modules, dev artifacts inside | **PASS** |
| Cargo.lock shipped? | No — hashed in manifest only (decision recorded) |
| Outer archive SHA-256 | recorded at build time; final value in the release message + `release/SHA256SUMS.zip` |

## L. Frontend audit (P2)

| Check | Result |
|---|---|
| No `innerHTML`/`outerHTML`/`eval`/`document.write` with untrusted data (source audit of `web/`) | **PASS** |
| No tokens in `localStorage`/`sessionStorage`/URLs | **PASS** |
| User/camera values inserted via `textContent`/escape helper | **PASS** |
| Same-origin only (CORS off) | **PASS** |

## M. Items NOT TESTED (with exact reason)

| Item | Status | Reason |
|---|---|---|
| Fresh install on **Ubuntu 22.04 / 24.04 x86_64** | **NOT TESTED** | Sandbox is Debian 13 ("trixie"); Ubuntu-equivalent tooling and systemd semantics, but no Ubuntu VM/container is available in this environment. Installer/upgrader logic (root checks, `os-release` gating, apt-less deps, systemd) was exercised on Debian with `sudo`. |
| Real camera hardware / WAN RTSP / GPU | **NOT TESTED** | No such hardware in sandbox; RTSP verified with real MediaMTX + ffmpeg publisher. |
| Multi-machine deployment | **NOT TESTED** | Single-host packaging model. |

Every other mandated item is **PASS** with the evidence above. No FAIL
items in this release. See `docs/RELEASE-REPORT-v1.0.2.md` for the
phase-by-phase record and final classification.
