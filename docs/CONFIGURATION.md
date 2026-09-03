# Configuration — v1.0.2

All settings live in `/etc/cctv-server/config.toml` (0640). The release
template is `config/config.example.toml`. The server validates the file
at startup and refuses to start on invalid values. `cctv-server health
--config <path>` validates without starting; `cctv-server env-guard
--config <path>` additionally checks ffmpeg, directory writability and
database openability (used by the installer/upgrader).

## Key sections

```toml
[server]
host = "0.0.0.0"     # bind address — 127.0.0.1 for same-machine / behind proxy
port = 8080          # must be > 0 (validated)

[storage]
recordings_dir = "/var/lib/cctv-server/recordings"
snapshots_dir  = "/var/lib/cctv-server/snapshots"
database_dir   = "/var/lib/cctv-server/database"
data_dir       = "/var/lib/cctv-server/state"
retention_days = 7
low_disk_warning_percent  = 90
critical_disk_percent     = 97

[database]
path = "/var/lib/cctv-server/database/cctv.db"   # relative → joined to database_dir

[logging]
level = "info"       # trace|debug|info|warn|error
file  = "/var/log/cctv-server/cctv-server.log"   # omit for stderr/journald
format = "text"      # text | json (daily rotation)

[auth]
default_admin_user = "admin"
default_admin_password = ""        # LEAVE EMPTY (random bootstrap on first init)
session_ttl_seconds = 86400
token_length = 48
max_login_attempts = 10
rate_limit_window_seconds = 300
lockout_seconds = 300
require_auth_for_api = true
cookie_secure = false              # true only when served over HTTPS
# secrets_file = "/etc/cctv-server/secrets.env"   # optional; unset by default

[security]
cors_allowed_origins = []          # same-origin dashboard by default

[hardware]
acceleration = "auto"              # auto | none | vaapi | qsv

[ai]
model_dir = "/opt/cctv-server/models"
model_file = "yolov8n.onnx"
default_max_fps = 2.0   # per-camera AI budget on CPU
...
```

> Removed in v1.0.2: `jwt_secret`/`JWT_SECRET` (never used — sessions are
> opaque server-side tokens) and `hardware.iqpu_vendor_ids` (dead config,
> no consumer). Unknown keys in config or secrets files are ignored for
> forward compatibility.

## Secrets

No secrets are required at runtime. The optional `secrets_file`
(`KEY=VALUE`, 0600) is parsed leniently; unknown keys ignored. The
packaged unit still passes it via systemd `EnvironmentFile=` (root-owned
0600). If you set `secrets_file`, the file must be readable by the
service user or startup fails with a clear message (by design).

## Bootstrap password precedence (v1.0.2)

1. `auth.default_admin_password` in config — operator intent, use only
   for unattended bootstrap, then remove it.
2. `CCTV_ADMIN_PASSWORD` environment variable passed to `init` —
   transient, never persisted.
3. Random 24-character CSPRNG password — printed once, optionally written
   once to `--password-file` (0600), deleted after display.

`init` never overwrites an existing admin user (idempotent).

## Storage & retention

- Segmented MP4s (copy/remux) under `recordings/<camera-id>/`.
- `retention_days` prunes old segments; disk thresholds emit warnings and
  events (`low_disk_warning_percent` / `critical_disk_percent`).
- `cctv-server storage status` prints disk/retention state.

## Health / readiness / version / metrics

- `GET /api/health` — liveness + db (200 when ok).
- `GET /api/ready` — **readiness**: db opens + `integrity_check == ok` +
  admin user present (200 only when all true; 503 otherwise). The
  installer and upgrader wait on this.
- `GET /api/status`, `/api/system`, `/api/storage`, `/api/version`,
  `/api/metrics`, `/api/config` (redacted).
- CLI: `status`, `health`, `storage status`, `db info|integrity|backup`,
  `env-guard`, `model list|validate|install`, `camera list|show`.

## Database tooling (v1.0.2)

```bash
cctv-server db info --config /etc/cctv-server/config.toml
cctv-server db integrity --config /etc/cctv-server/config.toml   # PRAGMA quick_check
cctv-server db backup --config /etc/cctv-server/config.toml /var/backups/cctv.db.snapshot
```

`db backup` uses the **SQLite Online Backup API** → a transactionally
consistent snapshot even while the service is live; it then re-opens the
target and runs `quick_check`. It refuses to overwrite an existing
target. Backups taken during `upgrade.sh` follow the same path.

## Rate limiting

`max_login_attempts` (10) failures per IP+username within
`rate_limit_window_seconds` (300) → `429` + `retry_after_seconds`;
correct passwords are refused during the lockout; success resets.

## Resource limits

- HTTP request body limit: 1 MB (axum `DefaultBodyLimit`).
- Bounded AI queue (`ai.queue_capacity`, default configured);
  broadcast event bus cap 256.
- systemd: `LimitNOFILE=65536`, `LimitNPROC=1024`, `TasksMax=512`.

## cookie_secure / HTTPS

- HTTP LAN (default): `cookie_secure = false` — cookies sent over http.
- HTTPS (direct or reverse proxy with TLS): set `cookie_secure = true`
  so browsers only send the cookie over https. Never claim HTTPS support
  unless your deployment actually terminates TLS (reverse proxy docs in
  `docs/OPERATIONS.md`).
