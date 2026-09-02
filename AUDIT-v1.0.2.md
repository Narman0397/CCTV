# Source Audit — v1.0.2 (final)

**Date:** 2026-09-02
**Version audited:** cctv-server 1.0.2 (git working tree at tag
`v1.0.2`; `VERSION` = `1.0.2`)
**Method:** source-level inspection of the whole tree
(`src/` + `crates/`), automated regex inventory of panic surfaces, and
live verification of security-critical claims. Every claim below is
either a source citation (file:line at audit time) or a pointer to
`VERIFICATION-v1.0.2.md` where it was exercised live.

---

## 1. Scope & architecture (as audited)

Single-binary modular monolith: one executable `cctv-server`, one
service, one config. Rust workspace:

| Crate/dir | Role | Key files |
|---|---|---|
| `src/` | binary: CLI, bootstrap (`init`/`cleanup`), benchmark, monitor | `main.rs cli.rs app.rs benchmark.rs` |
| `cctv-core` | config, DB, users, camera model, security helpers, metrics | `config.rs db.rs users.rs camera.rs security.rs` |
| `cctv-camera` | camera engine, RTSP analyzer, recorder control, AI worker | `engine.rs analyzer.rs ai_worker.rs recorder_ctl.rs` |
| `cctv-video` | ffmpeg probe + argument construction + process supervision | `ffmpeg.rs process.rs` |
| `cctv-ai` | detector (ONNX/ORT + Null fallback), motion pre-filter, adaptive scheduler | `detector.rs motion.rs scheduler.rs` |
| `cctv-api` | axum routes, auth, session state, WS, media | `lib.rs handlers.rs auth.rs state.rs ws.rs` |
| `cctv-events` | event engine (cooldown) | `lib.rs` |
| `cctv-recording` | segment naming/index | `lib.rs` |
| `cctv-storage` | disk status, retention | `lib.rs` |
| `cctv-tracking` | IoU tracking | `lib.rs` |

~8,700 lines of Rust. External processes: supervised FFmpeg helpers only
(`cctv-video`). MediaMTX is used only in tests as the RTSP broker.

## 2. Runtime panic surface — final inventory: **0**

Automated scan of `src/` + `crates/` (all `.rs`), excluding
`crates/*/tests/` integration dirs and `#[cfg(test)]`/`mod tests` blocks,
for `unwrap()` / `expect()` / `panic!` / `todo!` / `unimplemented!` /
`unreachable!` / `assert!` / `assert_eq!` / `assert_ne!`:

```
TOTAL runtime hits: 0
```

All remaining occurrences are TEST-ONLY (classification B) inside
`crates/cctv-api/tests/auth_api.rs`, `crates/cctv-core/tests/db_tests.rs`,
`crates/cctv-camera/tests/camera_lifecycle.rs`. The one non-test match
in `crates/cctv-core/src/error.rs` is inside a doc comment.

### Disposition of the v1.0.1 runtime hits (audit record)

| Location (v1.0.1) | Class | v1.0.2 disposition |
|---|---|---|
| `cctv-api/src/auth.rs` header `HeaderValue::from_str(...).unwrap()` (×3) | A — literal/constant strings | converted to infallible construction |
| `cctv-api/src/handlers.rs` Content-Range/Type/Length/Cache-Control literal `.unwrap()` (×7) | A | converted to infallible construction |
| `src/app.rs` ctrl-c `expect` | A | removed; graceful-shutdown future without `expect` (`app.rs:304-333`) |
| `src/app.rs` SIGTERM `expect` | A | SIGTERM handler install failure now logged and service continues (`app.rs:320-325`) |

No classification D/E/F (recoverable/security-sensitive/unknown) hits
were found in the audited tree. Policy enforced at review time: typed
`Result`/`Option` everywhere a runtime failure is possible; production
code contains no `unwrap/expect/panic` at all.

## 3. Authentication & sessions (architecture preserved, hardened)

`cctv-api/src/auth.rs`, `state.rs`, `cctv-core/src/users.rs`:

- Passwords: Argon2id, random salt via `OsRng`; never stored in
  plaintext.
- Session tokens: **opaque**, 48 bytes from OS CSPRNG
  (`state.rs:301-307` `random_token`), alphanumeric charset.
  **Stored SHA-256-hashed** (`state.rs:313` `hash_token`; map key =
  hash, `state.rs:165-201`) — a dump of the session map never yields a
  usable token; token comparison happens through the hash, avoiding
  timing correlation on the raw token.
- Cookie `cctv_session`: `HttpOnly; SameSite=Strict; Path=/;
  Max-Age=<ttl>`; `Secure` appended only when `auth.cookie_secure=true`
  (`auth.rs` cookie construction). Tokens are never accepted from query
  strings/URLs (verified 401), never logged.
- Rate limiting: per `(source IP, username)`; in v1.0.2 the three
  parameters are configurable: `auth.max_login_attempts`
  (default 10), `auth.rate_limit_window_seconds` (300),
  `auth.lockout_seconds` (300) — wired into
  `LoginRateLimiter::new(...)` in `cctv-api/src/state.rs`. Verified
  live: 429 with `retry_after_seconds`; correct password also refused
  during lockout; identical error body for wrong password vs. unknown
  user (no enumeration).
- Session lifecycle: lazy expiry + periodic eviction task
  (`state.rs:206-207` `evict_expired_sessions`); logout destroys the
  session; password change invalidates every other session of that user
  (PASS: live test §D-15 + `auth_api.rs`). No idle timeout (TTL only) — KNOWN
  LIMITATION for high-security deployments.
- Middleware (`auth.rs`): cookie first, then `Authorization: Bearer` /
  `x-api-token`; `/health`, `/ready`, `/auth/login`, `/auth/info`
  public; everything else and `/ws` require a session.

## 4. JWT — confirmed never used, removed (P1-13)

Trace of the v1.0.1 `jwt_secret` config field:
- declared `cctv-core/src/config.rs`; parsed from `JWT_SECRET` in the
  optional secrets file; **only validation existed** — no signing, no
  verification, no `jsonwebtoken` crate in `Cargo.lock` (checked), no
  `EncodingKey`, no token decode.
- Sessions are opaque server-side tokens; JWT was dead config.

v1.0.2 removes all `JWT_SECRET` generation/config/validation/docs/
redaction. A unit test keeps the secrets-file parser accepting a legacy
`JWT_SECRET=...` line and ignoring it (forward compatibility), proving
the removal is safe (`config.rs:500-508`).

## 5. Bootstrap admin password — P0 fixed (P0-1)

Final flow (`src/cli.rs`, `src/app.rs`, `scripts/install.sh`):

1. First `init` with no configured password and no env var generates a
   random 24-character password from the OS CSPRNG.
2. It is printed to the console once and — when the installer runs
   `init --password-file /etc/cctv-server/.bootstrap-admin-password` —
   written once to that root-only 0600 file.
3. The password is Argon2id-hashed into the DB immediately.
4. The installer prints it and **deletes the file** after readiness
   passes. `cctv-server cleanup` also removes a stale bootstrap file
   (`cli.rs:65,201-204`).
5. Plaintext exists only in the operator's terminal and transiently in
   the 0600 file — **never** in `secrets.env`, `config.toml`, the
   database, logs, journal, or release files. Verified live and by
   release scans.
6. Non-interactive automation: `CCTV_ADMIN_PASSWORD` env var read by
   `init` only, never written/echoed/logged, to be unset afterwards —
   documented procedure (`INSTALL.md`).
7. `init` never overwrites an existing admin user (idempotent).

Precedence: config `default_admin_password` → env `CCTV_ADMIN_PASSWORD`
→ random CSPRNG.

## 6. SQLite layer (P1-5 area)

`cctv-core/src/db.rs`:
- `Connection` behind `Mutex`; WAL; `foreign_keys=ON`;
  `busy_timeout=5000 ms`; schema version = `PRAGMA user_version`
  (`SCHEMA_VERSION = 1`, `db.rs:29`).
- `migrate()` (`db.rs:52`): **refuses to open a database whose
  `user_version` is newer than this binary supports** (`db.rs:55-59`) —
  downgrade guard; runs idempotent `CREATE TABLE IF NOT EXISTS ...`
  when version == 0 and records `user_version`; forward migrations
  are an explicit list (hook at `db.rs:130-133`).
- `integrity_check()` (`db.rs:149-153`): `PRAGMA quick_check`.
- `backup_to(path)` (`db.rs:160-193`): SQLite **Online Backup API**
  (`rusqlite::backup::Backup`) — transaction-consistent snapshot while
  the source is live; refuses to clobber an existing target; re-opens
  the target and runs `quick_check` before reporting success.
- All writes use `params!`; no SQL string interpolation with user data.

## 7. FFmpeg / RTSP / filesystem / media

- FFmpeg spawned with argument vectors only; no `sh -c` in runtime
  paths.
- RTSP URL validation (`cctv-core/src/security.rs`): scheme must be
  `rtsp://` (case-insensitive); rejects whitespace/control characters,
  `..`, backslashes, `file://`, `http://`, `unix:`; LAN/loopback
  allowed by design (CCTV sources are on the LAN). Credential redaction
  helpers (`redact_url`, `redact_credentials_in_text`) used in logs,
  status, and API output.
- Media serving (`cctv-api/src/handlers.rs`): canonicalization +
  allow-list prefix under the configured recordings/snapshots
  directories; traversal attempts verified 403/404 (live, including
  percent-encoded). Range requests supported with bounded chunking.
- Model path (`src/cli.rs` `model validate`): existence/size/protobuf
  sanity + real ONNX Runtime load test; missing ORT library → clear
  error, exit 1, **no crash** (verified).

## 8. Queues / backpressure / degradation (P1 area)

- AI work queue: bounded `mpsc::channel(capacity)` —
  `cctv-camera/src/ai_worker.rs:51`; capacity from config
  `[ai] queue_capacity` (`cctv-camera/src/engine.rs:251` →
  `config.rs:204`); full queue drops frames (backpressure, never
  unbounded).
- Event bus: `tokio::sync::broadcast::channel(256)` (`src/app.rs:213`).
- Degradation order: AI drops/degrades first; recording and the camera
  loop keep running (motion-only mode without a model; live-tested).
- No unbounded channels found in runtime paths.

## 9. Config parsing & validation

- `#[serde(default)]` on every config struct; unknown keys in
  `config.toml` and in the secrets file are **ignored** (forward
  compatibility), with tests (`config.rs:500-508`).
- `Config::validate()` (`config.rs:443`): rejects invalid values with
  specific messages — `server.port > 0`, `auth.session_ttl_seconds >
  0`, `recording.segment_seconds > 0`, etc.
- Removed in v1.0.2: `hardware.iqpu_vendor_ids` (audited: declared but
  **no consumer** anywhere in the tree — dead/obsolete option;
  removal is source-confirmed, not guessed) and all JWT remnants.
- `auth.secrets_file` is optional and commented out in the shipped
  template; if set, the file must be readable or startup fails with a
  clear message (by design).

## 10. HTTP/WS hardening

- Body limit 1 MB (`cctv-api/src/lib.rs:29` `DefaultBodyLimit`).
- Graceful shutdown: Ctrl-C/SIGTERM without `expect` (`app.rs:304-333`);
  SIGTERM handler install failure is logged, not fatal.
- Error responses generic (no stack traces, no internal paths).
- CORS off by default (`cors_allowed_origins = []`).

## 11. Installer / upgrade / uninstall / systemd (P1-5..12)

`scripts/install.sh`, `scripts/upgrade.sh`, `scripts/uninstall.sh`,
`systemd/cctv-server.service` (source of what the release ships; the
installed copy lives at `/etc/systemd/system/`):

- Installer: SCRIPT_DIR/RELEASE_DIR resolution (works from any CWD);
  root/OS/arch checks; `cctv` user; layout + permissions; empty 0600
  `secrets.env` (no secret required); `env-guard` gate; `init
  --password-file`; start + wait on **`/api/ready`** up to 45 s; if the
  service never becomes ready it prints the journal tail and **exits
  non-zero** (never reports success for an unhealthy service);
  auto-deletes the bootstrap file after success; idempotent on reinstall
  (config kept with timestamped backup, admin password unchanged).
- Upgrader: verifies the running install (binary + DB openable) and the
  package (`SHA256SUMS` inside the ZIP checked with `sha256sum -c`;
  version/arch checks; **downgrade refused**); dependency + env-guard
  with the new binary; stop → consistent DB snapshot via
  `cctv-server db backup` (Online Backup API, not `cp`) + full backup of
  config/secrets/old binary/unit/web/docs/VERSION/manifest → replace all
  artifacts → idempotent migrations → validate (`db integrity`) → start
  → `/api/ready` → smoke checks → mark success. Any failure triggers
  automatic rollback of **all** artifacts **plus the consistent DB
  snapshot**, then restart of the previous version. Verified live:
  successful 12-step upgrade; injected failure (broken unit) rolled back
  cleanly.
- Uninstaller: normal + `--purge` (deletes data after explicit
  confirmation).
- systemd unit: `Documentation=file:///opt/cctv-server/docs/README.md`
  — the installer/upgrader ship the repo README to that exact path
  (P1-11, verified with `systemd-analyze verify`, exit 0). Hardening
  score measured: `systemd-analyze security` = **3.6 OK**.

## 12. Frontend (P2)

- No `innerHTML`/`outerHTML`/`eval`/`document.write` with untrusted
  data; user/camera-supplied values inserted with `textContent` or the
  escape helper; no tokens in `localStorage`/`sessionStorage`/URLs;
  same-origin dashboard (CORS off); media elements use authenticated
  fetch + blob URLs.

## 13. Known limitations (recorded, not hidden)

1. Ubuntu 22.04/24.04 fresh-install runs: **NOT TESTED** in this
   sandbox (Debian 13, Ubuntu-equivalent tooling; no Ubuntu VM).
   Installer/upgrader logic verified on Debian with `sudo`.
2. Login rate limiter is in-memory (resets on restart) — documented.
3. No session idle timeout (absolute TTL only).
4. Default bind `0.0.0.0:8080` is intentional for LAN CCTV; internet
   exposure requires a TLS reverse proxy + `127.0.0.1` bind +
   `cookie_secure=true` (documented).
5. CPU-only AI throughput is ~1–2 FPS per camera with several cameras
   (measured); not the old 10 FPS/camera spec target.
6. Release built and verified on x86_64 only.

## 14. Conclusion

After the v1.0.2 hardening pass the runtime panic inventory is **zero**
in production code, the bootstrap secret is never persisted, upgrades
are transactional with consistent DB snapshots and full rollback, and
release artifacts are synchronized with an internal `SHA256SUMS` and
`RELEASE-MANIFEST.json`. Details of execution and per-item statuses:
`docs/VERIFICATION-v1.0.2.md` and `docs/RELEASE-REPORT-v1.0.2.md`.
