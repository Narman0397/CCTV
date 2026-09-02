# Testing — v1.0.2 (overview)

Full evidence with commands, outputs and statuses lives in
`docs/VERIFICATION-v1.0.2.md`. This page is a quick index. No fake or
self-approving tests: everything below was executed against the real
v1.0.2 build during the release process.

## Quality gates (all green at release time)

```bash
cargo fmt --check                          # clean
cargo clippy --all-targets --all-features -- -D warnings   # 0 warnings
cargo test --workspace                     # 46 passed, 0 failed
cargo audit                                # 0 vulnerabilities (242 deps)
cargo build --release --bin cctv-server    # OK
```

## Test suites

| Suite | Scope | Result |
|---|---|---|
| `cargo test --workspace` | unit + integration: storage, recording indexer, AI scheduler + motion, tracking IoU, events cooldown, camera snapshot, config validation, DB (integrity/backup/migration guard), security/auth (Argon2id, sessions, rate limit, redaction, traversal), CLI | 46/46 PASS |
| `crates/cctv-core/tests/db_tests.rs` | DB: 50 users round-trip, online-backup snapshot consistency, refuse-clobber backup, schema-version guards | 8/8 PASS |
| `crates/cctv-api/tests/auth_api.rs` | auth API: cookie flags, login/logout, lockout/429, password change session invalidation, bearer, traversal, rate limit | 8/8 PASS |
| `camera_lifecycle` (gated E2E) | real MediaMTX + real ffmpeg H.264 publisher: connect → frames → MP4 segments → disconnect → `camera_offline` → reconnect → `camera_restored` | PASS (23.22 s) |

## Live checks executed (see VERIFICATION doc for details)

- Login brute force / lockout matrix (401/429 identical-body, no
  enumeration), cookie + Bearer auth, `?token=` rejected, WS auth,
  media traversal, `/api/ready` gating.
- Bootstrap flow: random password printed once, Argon2id in DB, 0600
  file auto-deleted after install, no plaintext in secrets/config/log/
  journal.
- Installer: fresh install + reinstall idempotency + `systemd-analyze
  security` (**3.6 OK**) + `env-guard` + readiness gate.
- Upgrader: full transactional upgrade from the official ZIP (12 steps),
  consistent DB snapshot backup via Online Backup API, automatic
  **rollback** under injected failure (broken unit → service restored,
  data intact).
- Model CLI: `validate` OK with real ONNX; `load-test: FAILED` (exit 1,
  no crash) without the ORT library.
- Benchmark: real-frame motion/jpeg/copy/disk measurements and real
  YOLOv8n CPU inference (~83–88 ms/inference; sustained ~12 FPS
  aggregate on this host).
- Release integrity: inner `SHA256SUMS` verified 22/22 OK;
  `RELEASE-MANIFEST.json` fields checked; release scanned for
  credentials/keys (clean).

## Not performed

- **Fresh install on Ubuntu 22.04 / 24.04** — NOT TESTED: the sandbox is
  Debian 13 (Ubuntu-equivalent tooling); no Ubuntu VM is available.
  Installer/upgrader were verified on Debian with `sudo`.
