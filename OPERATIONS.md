# Operations — v1.0.2

## Service management

```bash
systemctl status cctv-server            # status + recent log
journalctl -u cctv-server -f            # live logs
systemctl restart cctv-server           # restart
sudo systemctl stop cctv-server         # stop
```

Runs as unprivileged `cctv`; writes only under `/var/lib/cctv-server`
and `/var/log/cctv-server`.

## Readiness & health

```bash
curl -s http://127.0.0.1:8080/api/health     # liveness + db
curl -s http://127.0.0.1:8080/api/ready      # readiness (db integrity + admin present)
cctv-server health --config /etc/cctv-server/config.toml   # CLI, exit code
cctv-server env-guard --config /etc/cctv-server/config.toml
```

`/api/ready` returns 200 only when the database opens, passes
`PRAGMA quick_check`, and the admin user exists; otherwise 503. The
installer/upgrader treat non-ready as failure.

## Monitoring

- `GET /api/status` — per-camera state (`connected`, `fps`,
  `last_error`, `reconnect_count`).
- `GET /api/storage` — disk + recording growth; `storage status` CLI.
- `GET /api/metrics` — counters (frames, dropped frames, inference
  count/latency, reconnects, queue pressure, db errors, disk/ram,
  recording bytes).
- Logs: `WARN ... reconnect in progress camera=... backoff_ms=...` —
  camera down; exponential backoff retries; recording resumes
  automatically on reconnect.

## Database backup / integrity (v1.0.2)

```bash
# transaction-consistent snapshot (Online Backup API) — safe while live
cctv-server db backup --config /etc/cctv-server/config.toml /var/backups/cctv.db.20260902
# verify
cctv-server db integrity --config /etc/cctv-server/config.toml
cctv-server db info --config /etc/cctv-server/config.toml
```

Do **not** `cp` a live WAL database for backups — use `db backup`. Add a
cron/systemd-timer wrapper if you want scheduled snapshots. `upgrade.sh`
creates a consistent snapshot automatically before touching files.

## Models (AI)

```bash
sudo -u cctv cctv-server model list --config /etc/cctv-server/config.toml
sudo -u cctv cctv-server model validate --config /etc/cctv-server/config.toml \
     --model /opt/cctv-server/models/yolov8n.onnx
sudo -u cctv cctv-server model install --config /etc/cctv-server/config.toml \
     https://example.com/yolov8n.onnx
```

- `model validate` = header + size + optional sha256 pin + **real ONNX
  Runtime load test** (`load-test: ok`); exits 1 (no crash) when the ORT
  library is missing — set `ORT_DYLIB_PATH` if it is not in loader paths.
- Missing/corrupt model → motion-only mode; recording and API keep
  working (verified).

## Adding cameras

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<pw>"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

curl -X POST http://127.0.0.1:8080/api/cameras \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"Lobby","rtsp_url":"rtsp://user:pass@host/stream1",
       "width":1280,"height":720,"fps":15,"recording":true,
       "ai_enabled":true,"motion_enabled":true}'
```

Only `rtsp://` URLs accepted; credentials are redacted from logs/API.

## Backups & restore

- `upgrade.sh` keeps `/var/backups/cctv-server-<stamp>/` (binary, config,
  secrets, systemd unit, web, docs, VERSION, manifest, and a consistent
  DB snapshot `cctv.db.consistent`).
- Scheduled: copy `/etc/cctv-server/`, run `db backup`, and snapshot
  `/var/lib/cctv-server/recordings/` (bulk) with your storage tooling.

Restore:

```bash
sudo systemctl stop cctv-server
sudo cp /var/backups/cctv-server-<stamp>/cctv.db.consistent /var/lib/cctv-server/database/cctv.db
sudo cp /var/backups/cctv-server-<stamp>/config.toml /etc/cctv-server/
sudo cp /var/backups/cctv-server-<stamp>/secrets.env /etc/cctv-server/   # if present
sudo chown -R cctv:cctv /var/lib/cctv-server
sudo systemctl start cctv-server
```

## Lost admin password

The first-run password is deliberately not stored anywhere (the
temporary 0600 bootstrap file is deleted by the installer). If the
admin password is lost:

```bash
sudo systemctl stop cctv-server
sudo mv /var/lib/cctv-server/database/cctv.db{,-lost-$(date +%s)}   # keep for forensics
sudo -u cctv /opt/cctv-server/bin/cctv-server init --config /etc/cctv-server/config.toml
sudo systemctl start cctv-server
```

A fresh admin user is created and its random password printed once.
Recordings on disk are preserved; camera metadata/events reset (the old
database file is kept beside the new one). Alternatively, set
`auth.default_admin_password` in `/etc/cctv-server/config.toml` before
the first `init` of a fresh database and remove it afterwards.

## Secret / password rotation

- Admin password: `POST /api/auth/password` (all other sessions
  invalidated). Delete leftover `/etc/cctv-server/.bootstrap-admin-password`
  (`sudo cctv-server cleanup`).
- Camera credentials: `PATCH /api/cameras/<id>` with new `rtsp_url`.
- No shared JWT secret exists in v1.0.2 to rotate.

## Capacity notes (measured)

See `docs/PERFORMANCE.md` / `docs/BENCHMARKS.md` for the measured
numbers (2-core reference host):
- 10 cameras 320×180@10 motion+record, no AI: server ~0.9% CPU / ~14 MB
  RSS; ffmpeg workers dominate (~1.1 GB RSS for 20 workers).
- CPU AI (YOLOv8n 640²): ~83–88 ms/inference; sustained ~1.7 FPS per
  camera with concurrent cameras. Plan 1–2 FPS/camera on CPU or use a
  GPU. Do not claim 10 FPS/camera on CPU.
- Recordings are remuxed; disk ≈ source bitrate. Use `retention_days`.

## Logs

- Text or JSON to `/var/log/cctv-server/cctv-server.log`, daily rotation;
  unwritable → warning + stderr fallback (never a crash).
- RTSP credentials redacted in all log lines.
- If the log volume matters, add OS-level logrotate for
  `/var/log/cctv-server/*.log*`.

## Reverse proxy / HTTPS

```nginx
# nginx example — terminate TLS, proxy to the local service
server {
  listen 443 ssl;
  server_name cctv.example.com;
  ssl_certificate     /etc/letsencrypt/live/cctv.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/cctv.example.com/privkey.pem;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;      # WebSocket
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
  }
}
```

With `server.host = "127.0.0.1"` in the config and
`auth.cookie_secure = true`, cookies are only sent over HTTPS.
