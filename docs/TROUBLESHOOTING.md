# Troubleshooting

## Service won't start

```bash
sudo journalctl -u cctv-server -n 50
sudo systemctl start cctv-server   # watch for errors
```

Common causes and fixes:

| Symptom | Cause / fix |
|---|---|
| `cannot read config file ...` | Config unreadable by `cctv`: check `/etc/cctv-server` is `0750 root:cctv` and `config.toml` is `0640 root:cctv` (installer sets this; after a manual copy, re-run `chown root:cctv`). |
| `cannot read secrets file ... Permission denied` | `secrets.env` must be `0600 root:root` and injected via `EnvironmentFile=` (unit does this). If you run `cctv-server init` as `cctv` directly it cannot read the file — run init as root. |
| `Address already in use` | Another process on the configured port: `ss -tlnp \| grep :8080`. |
| `ffmpeg not found` | `sudo apt install -y ffmpeg`. |
| Exits immediately with a config error | Run `cctv-server health --config /etc/cctv-server/config.toml` to see the validation error. |
| Unit shows `StartLimitIntervalSec` warnings | Old unit on disk — reinstall: `sudo ./scripts/install.sh` (or copy `systemd/cctv-server.service`). |

## Camera shows `connected: false`

Check the camera `last_error`:

```bash
curl -s http://127.0.0.1:8080/api/cameras -H "Authorization: Bearer $TOKEN"
```

- `Error opening input files: Server returned 404 Not Found` — wrong RTSP
  path or the stream is not running. The state machine keeps retrying with
  exponential backoff; no manual action needed once the source returns.
- `401 Unauthorized` / `403 Forbidden` from the camera — wrong credentials
  in the RTSP URL. Fix via `PATCH /api/cameras/<id>`.
- Firewall/NAT: the server must reach the camera's RTSP port (554 by
  default) and RTP ports in both directions.

## Recording stops but the server is up

- Check `recording` is `true` on the camera and the disk is not full:
  `curl -s http://127.0.0.1:8080/api/storage`.
- Check the service user can write: `sudo -u cctv touch /var/lib/cctv-server/recordings/.wtest`
- If `recording` segments are empty/zero-byte, the source uses a codec the
  remuxer can't copy — set the camera `format`/`container_muxer`, or
  enable decode (`hardware_encode=false` + `format="h264"` pipeline) to
  transcode as a fallback.

## AI is not detecting anything

```bash
curl -s http://127.0.0.1:8080/api/health   # check "ai_model_loaded"
cctv-server model list --config /etc/cctv-server/config.toml
cctv-server model validate --config /etc/cctv-server/config.toml \
     --model /opt/cctv-server/models/yolov8n.onnx
```

- `ai_model_loaded: false` → model missing. `model install` it and
  restart.
- `load-test: FAILED (ONNX Runtime library not found ...)` → set
  `ORT_DYLIB_PATH` to a `libonnxruntime.so`, or install
  `libonnxruntime`/onnxruntime and restart.
- `detections_total` stays 0 with a valid model → the scene has no objects
  of interest, or `conf_threshold` is too high / `motion` pre-filter
  suppresses frames (check `motion_frames_total`).

## Client says 401 / 429

- `401` — no/expired session: send `Authorization: Bearer <token>` or the
  `cctv_session` cookie. Tokens in the URL are not supported.
- `429 Too Many Requests` with `retry_after_seconds` — too many failed
  logins from your IP; wait, then retry (counter resets on success or
  server restart).

## Login works but the dashboard is broken

- Dashboard is a single static `index.html` served from the same origin —
  check `/opt/cctv-server/web/index.html` is intact (reinstall restores
  it) and that you reach the server on the same host/port as the API.
- Browser must allow the `cctv_session` cookie (same-origin, HTTPS not
  required on LAN but use TLS behind a proxy for the internet).

## Logs fill the disk

- Daily rotation is built in; set a log retention policy at the OS level
  (`logrotate`) for `/var/log/cctv-server/*.log*`. Recordings are the main
  disk consumer — tune `recording.retention_days`.

## Still stuck?

Gather and include in any bug report:

```bash
cctv-server version
systemctl status cctv-server
sudo journalctl -u cctv-server -n 200
curl -s http://127.0.0.1:8080/api/status
curl -s http://127.0.0.1:8080/api/metrics
```
