# cctv-server v1.0.2

**AI video surveillance server** — a single modular-monolith Rust
application that manages cameras, ingests RTSP streams, records
(copy/remux, no re-encode), runs YOLO object detection with an adaptive
scheduler and motion pre-filtering, keeps metadata in SQLite (WAL), and
serves a REST API, WebSocket push and a web dashboard — all in **one
executable, one service, one config**.

- Targets **Ubuntu 24.04 / Debian 13 x86_64 (GLIBC 2.39+)**. The shipped
  `bin/cctv-server` **does not run on Ubuntu 22.04 or Debian 12**
  (`GLIBC_2.39 not found`). Verified build host was glibc 2.39+; see
  `docs/VERIFICATION-v1.0.2.md`.
- Production packaging: hardened systemd unit, dedicated `cctv` user,
  `/opt/cctv-server/` + `/etc/cctv-server/` + `/var/lib/cctv-server/`
  layout, idempotent installer / transactional upgrader with automatic
  rollback / uninstaller.
- **No default credentials, no JWT, no shared secrets at runtime.**
  First-run admin password is random (OS CSPRNG), printed exactly once,
  written once to a 0600 root-only bootstrap file that the installer
  deletes; it is **never persisted** in `secrets.env`, config, DB, logs
  or journal. Passwords are Argon2id-hashed. Sessions are opaque
  48-byte server-side tokens stored SHA-256-hashed.
- Media/WS require `Authorization: Bearer` or the `HttpOnly` cookie —
  never `?token=` (verified 401). Path traversal blocked (verified
  403/404); RTSP credentials redacted in logs; ffmpeg runs with argument
  vectors (no shell); every queue is bounded.
- Measured performance (2-core CPU box, YOLOv8n ONNX): ~83–88
  ms/inference, ~1.7 AI FPS/camera live; 10 cameras without AI → server
  ~1% CPU / ~14 MB RSS. See `docs/PERFORMANCE.md` — the old "10
  FPS/camera AI" target is **not** achievable on CPU-only.

## Quick start (Ubuntu 24.04 / Debian 13 x86_64)

```bash
sudo apt update && sudo apt install -y ffmpeg unzip
unzip cctv-ai-server-1.0.2-linux-x86_64.zip -d ~/cctv-release
cd ~/cctv-release
sudo ./scripts/install.sh
```

The installer prints the **first-run admin password exactly once** and
starts the service (dashboard at `http://<host>:8080`). The installer
**exits non-zero** if the service does not become ready, and deletes the
bootstrap file afterwards. Change the password immediately via
`POST /api/auth/password` (see `docs/INSTALL.md`).

## Documentation

| Doc | Contents |
|---|---|
| `docs/INSTALL.md` | install / reinstall / upgrade / uninstall / checklist |
| `docs/SECURITY.md` | auth, hardening, secrets, rate limiting, systemd (3.6 OK) |
| `docs/CONFIGURATION.md` | every config option, secrets, cameras, retention |
| `docs/OPERATIONS.md` | service mgmt, monitoring, models, backups, restore |
| `docs/TROUBLESHOOTING.md` | common failures and fixes |
| `docs/PERFORMANCE.md` | measured benchmarks and honest AI capacity |
| `docs/ARCHITECTURE.md` | crate/component overview |
| `docs/TESTING.md` | how the release was verified (overview) |
| `docs/AUDIT-v1.0.2.md` | full source audit for this release |
| `docs/VERIFICATION-v1.0.2.md` | every check with PASS/FAIL/NOT TESTED + evidence |
| `docs/RELEASE-REPORT-v1.0.2.md` | release record: phases, artifacts, classification |
| `models/README.md` | how to install/validate the YOLO model |

## Layout

```
bin/cctv-server            release binary
web/index.html             dashboard
config/config.example.toml config template
systemd/cctv-server.service
scripts/install.sh         idempotent installer (sudo)
scripts/upgrade.sh         transactional upgrader with rollback (sudo)
scripts/uninstall.sh       uninstaller (--purge supported)
models/README.md
VERSION  LICENSE  README.md  RELEASE-MANIFEST.json  SHA256SUMS
docs/                      shipped documentation
```

## License

MIT — see `LICENSE`.
