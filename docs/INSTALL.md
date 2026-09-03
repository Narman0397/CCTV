# Installation — v1.0.2

cctv-server is packaged as a single self-contained ZIP targeting
**Ubuntu 24.04 / Debian 13 x86_64 (GLIBC 2.39+)**. Ubuntu 22.04 and
Debian 12 cannot execute the shipped binary. The installer is idempotent
and **fails (non-zero) if the service does not become ready**.

## Requirements

| Requirement | Minimum | Notes |
|---|---|---|
| OS | Ubuntu 24.04 or Debian 13 x86_64 | GLIBC **2.39+** required (`ldd --version`). Ubuntu 22.04 / Debian 12 will fail the installer libc check. |
| ffmpeg | 4.4+ | `sudo apt install -y ffmpeg` (required) |
| curl | any | only for `model install` |
| RAM | 1 GB (2–4 GB recommended) | see `docs/PERFORMANCE.md` |
| Disk | 10 GB+ | recordings grow with camera count/bitrate |

> GPU is optional. YOLO runs on CPU at a reduced rate; measure on your
> hardware (see `docs/PERFORMANCE.md`). Verified environment for this
> release: Debian 13 / systemd sandbox (Ubuntu-equivalent tooling) — see
> `docs/VERIFICATION-v1.0.2.md`.

## Install (fresh)

```bash
sudo apt update && sudo apt install -y ffmpeg unzip
unzip cctv-ai-server-1.0.2-linux-x86_64.zip -d ~/cctv-release
cd ~/cctv-release
sudo ./scripts/install.sh
```

The installer (each step is logged with `==>`):

1. Verifies root, OS (Ubuntu 22.04/24.04), architecture (`x86_64`) —
   fails safely otherwise.
2. Creates the `cctv` system user/group (no login shell).
3. Creates the layout (permissions below).
4. Installs binary, web dashboard, systemd unit, docs (including
   `docs/README.md`, the target of the unit's `Documentation=`) and
   `VERSION`.
5. Creates an empty `secrets.env` (0600) — **no secret is required at
   runtime**.
6. Runs `cctv-server env-guard` (ffmpeg present, directories writable,
   database opens) — aborts on failure.
7. Runs `cctv-server init --password-file
   /etc/cctv-server/.bootstrap-admin-password`: first-run **random admin
   password** printed once and written once to that 0600 file.
8. Starts the service, waits up to 45 s on **`/api/ready`** (db +
   integrity + admin user present). If readiness is not reached or the
   service dies, the installer prints the journal tail and **exits
   non-zero** — it never reports success for an unhealthy service.
9. Prints the admin password once more and deletes the bootstrap file.

### Installed layout

```
/opt/cctv-server/
  bin/cctv-server          binary (0755 root:cctv)
  web/index.html           dashboard (0644 root:cctv)
  models/                  put yolov8n.onnx here
  docs/                    shipped documentation (0644 root:cctv)
  VERSION  RELEASE-MANIFEST.json  SHA256SUMS
/etc/cctv-server/
  config.toml              config (0640 root:cctv)
  secrets.env              optional KEY=VALUE file (0600 root:root)
/var/lib/cctv-server/
  database/  recordings/  snapshots/  events/  state/   (0750 cctv:cctv)
/var/log/cctv-server/                                     (0750 cctv:cctv)
```

### First login

```bash
# password was shown by the installer and is NOT persisted anywhere else.
# Change it immediately:
curl -X POST http://127.0.0.1:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<first-run-password>"}'
curl -X POST http://127.0.0.1:8080/api/auth/password \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<old>","new_password":"<new-strong>"}'
```

All other sessions are invalidated automatically on password change.

### Non-interactive / automated installs

For automation you may supply a password through the environment so the
random bootstrap is skipped:

```bash
CCTV_ADMIN_PASSWORD='<strong-password>' \
  sudo -E /opt/cctv-server/bin/cctv-server init \
  --config /etc/cctv-server/config.toml --password-file /etc/cctv-server/.bootstrap-admin-password
# then unset the variable in your provisioning script
```

The password is only read from the environment, never written to disk,
logs or the unit file. For the fully automatic path, install with the
random password and immediately change it via the API in the same
provisioning run.

## Reinstall (same version, data preserved)

`sudo ./scripts/install.sh` again: existing `config.toml` kept (with a
timestamped backup), existing database/recordings untouched, existing
admin user left alone (init is idempotent). Verified: reinstall keeps the
admin password and data.

## Upgrade to a new version

```bash
sudo ./scripts/upgrade.sh /path/to/cctv-ai-server-<new>-linux-x86_64.zip
```

Transactional flow (each numbered step must succeed or an automatic
rollback runs):

1. Verify running installation (binary + database openable).
2. Verify package integrity: `SHA256SUMS` inside the ZIP is checked with
   `sha256sum -c`.
3. Version + architecture checks; **downgrade is refused** (migration
   policy: a newer schema is refused by the binary with a clear error, so
   rollback restores the old binary + a consistent DB snapshot).
4. Dependency check (ffmpeg) + `env-guard` with the new binary.
5. Stop service; create **transaction-consistent database backup** with
   the SQLite Online Backup API (`cctv-server db backup` — not `cp`), plus
   backups of config, secrets, old binary, unit, web, docs, VERSION,
   RELEASE-MANIFEST, SHA256SUMS to `/var/backups/cctv-server-<stamp>/`.
6. Replace **all** release artifacts (binary, web, unit, config template,
   docs, VERSION, manifest, SHA256SUMS).
7. Run migrations (`init` — idempotent).
8. Validate: `cctv-server health` + `db integrity`.
9. Start service; wait for `/api/ready` (45 s).
10. Smoke checks (`/api/health`, camera list).
11. Mark success in `upgrade-state`.
12. On any failure: rollback restores binary, web, unit, config, secrets,
    docs, VERSION, manifest **and the consistent DB snapshot**, then
    starts the previous service.

Verified in release: successful upgrade; failed upgrade (broken unit)
rolled back to the previous working installation with data intact.

## Uninstall

```bash
sudo ./scripts/uninstall.sh          # remove program + config, KEEP data
sudo ./scripts/uninstall.sh --purge  # also delete recordings, DB, logs, user (asks for "PURGE")
```

## Post-install checklist

- [ ] `systemctl status cctv-server` → `active (running)`
- [ ] `curl http://127.0.0.1:8080/api/ready` → `{"status":"ready",...}`
- [ ] Admin password changed from the first-run random one
- [ ] `/etc/cctv-server/.bootstrap-admin-password` removed (installer does
      this; `sudo cctv-server cleanup` also removes it)
- [ ] Optional AI: `sudo cp yolov8n.onnx /opt/cctv-server/models/ && sudo
      systemctl restart cctv-server`
- [ ] For internet exposure: TLS reverse proxy + `server.host=127.0.0.1`
      + `auth.cookie_secure=true` (see `docs/SECURITY.md`)
