# Architecture

## One binary, one service

`cctv-server` is a single `systemd` service. All subsystems live inside the one
master process (modular-monolith):

```
                     ┌───────────────────────────────────────────┐
                     │              cctv-server                   │
                     │                                            │
  RTSP cameras ───▶ │  ffmpeg (child, supervised)                │
   (H.264/720p)     │   ├─ analyzer pipe  → motion → AI → events │
                     │   ├─ recorder pipe → MP4 segments (copy)  │
                     │   └─ snapshot (on demand / event)         │
                     │                                            │
                     │  SQLite (WAL)  ◀── camera/event/detection │
                     │  storage sweeper (retention, disk safety) │
                     │  adaptive AI scheduler                    │
                     │  REST API + WebSocket + dashboard (axum)  │
                     └───────────────────────────────────────────┘
```

FFmpeg is the only external dependency and it is **always supervised**: the
master binary spawns it as a child, watches its exit status and stderr, and
restarts it with backoff. FFmpeg is never allowed to write outside paths the
server controls (recordings go through the server's own segment writer).

## Analyzer pipeline (per camera)

1. **Decode** — ffmpeg decodes the RTSP stream, emitting raw RGB frames
   (`-vf fps=N` throttles decode to the configured preview FPS — measured to
   be the correct throttle for RTSP; input-side `-r` does **not** throttle).
2. **Motion pre-filter** — a downscaled 160×90 luminance buffer is diffed
   against the previous frame; score = `mean_diff * sensitivity`. If
   `score < threshold`, the frame is **skipped by AI** (huge CPU saving on
   static scenes — cameras 20+ are only viable because of this).
3. **AI gate** — the adaptive scheduler decides, per camera, whether this
   frame is worth an inference (idle/motion/active tiers).
4. **AI** — ONNX Runtime YOLO (model optional; without a model the server
   runs motion-only gracefully — AI failure never stops recording).
5. **Tracking** — IoU tracking merges detections into tracks; tracks crossing
   `persist_seconds` produce detections; new tracks fire events with optional
   snapshot.

The recorder is a **separate ffmpeg child** doing `-c copy -f mp4` remux: it
records the full source rate (e.g. 30 fps) regardless of the analyzer rate.

## Bounded everything

| Resource | Bound | Behavior when hit |
|---|---|---|
| AI queue per camera | `queue_capacity` (default 2) | frame dropped, `frames_dropped` metric, no blocking |
| Broadcast bus | bounded channel | lagged subscribers skip, never block producers |
| Disk | `critical_disk_percent` (90%) | AI degraded first, then recorder gracefully stops new segments, sweepers run; server never fills disk silently |
| RAM | `ram_high_pressure_percent` (85%) | scheduler cuts AI rates to idle tier |
| CPU | `cpu_high_load_percent` (75%) / `cpu_critical_load_percent` (90%) | scheduler reduces active cameras / drops to motion-only |
| DB writes | WAL + busy timeout | bounded retries, errors counted, never panic |

Degradation order is always: **AI first → analyzer → recorder last**. NVR
recording is the protected core; camera or model failure must not stop it.

## Camera failure handling

- Analyzer stall/EOF → status `reconnecting`, reconnect with exponential
  backoff (`1s → 60s`, factor 2), `camera_offline` event after
  `offline_event_threshold_seconds`.
- Publisher/camera comes back → reconnects automatically,
  `camera_restored` event, recording resumes without operator action.
- A camera that never connects does not affect other cameras or the server
  (each camera runtime is isolated; errors are typed `Result`s, no
  `unwrap/expect/panic` in production paths).

## Storage

- Recordings: flat `recordings/<camera>/YYYY-MM-DD_HH-MM-SS.mp4` (10s–300s
  segments, copy/remux). Indexed into SQLite by a periodic scanner that walks
  the camera dir (flat or day-subdir layouts).
- Retention: sweeper deletes files older than `retention_days`
  (recordings/snapshots) and events older than `event_retention_days`.
- Safety: `low_disk_warning_percent` emits warnings; `critical_disk_percent`
  stops new recording gracefully; free space is measured, never assumed.

## Monitoring / health

- `/api/health` — liveness + DB check.
- `/api/status`, `/api/system`, `/api/metrics` — counters, gauges, scheduler
  state, disk/RAM/CPU pressure.
- `/api/storage` — bytes by category + warnings.
- WebSocket `/ws` — realtime `status` snapshots + event/detection broadcasts
  for the dashboard.
