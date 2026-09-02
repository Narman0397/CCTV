# Benchmarks — actual measured results

> Policy: **only real measurements**. All numbers in this file were
> produced by running the actual release binary (`cctv-server 1.0.2`) on
> the release reference host. Never fabricated; extrapolations are
> explicitly labelled.
>
> Reference host: 2 vCPU, 2 GB RAM, no GPU, ffmpeg 7.1.5, MediaMTX 1.11.2,
> ONNX Runtime 1.29.0 (CPU). Model: `yolov8n.onnx` (ultralytics release
> asset, 640×640).

## Built-in benchmark (authoritative)

`cctv-server benchmark` output on the reference host (2026-09-02):

```
cpu cores: 2
motion pre-filter (160x90 luma diff): 0.053 ms/frame
frame copy + arc store: 0.229 ms/frame
jpeg encode (720p, q80): 50.78 ms/frame (1255 KB)
disk write throughput: 1954.6 MB/s
YOLO inference (640x640, onnx CPU): 87.7 ms/inference (detections=0)
  => max sustained AI FPS on this machine: 11.4
```

## Live end-to-end measurements (real RTSP)

### Analyzer throttling (RTSP, testsrc2 source)

Baked into the code: **output-side `-vf fps=N` only** (input `-r` does not
throttle RTSP). Measured: `motion_frames_total` delta = 5/s at
`preview_fps = 5`.

### Recorder (copy/remux, no re-encode)

- 10 s MP4 segment, H.264 source: plays back at full source rate; the
  analyzer is throttled independently.
- Stress run (5 cameras 640×360@15; v1.0.1-era measurement, paths unchanged in v1.0.2): 20 segments, ~19.3 MB written
  in the measurement window, `recording_bytes_written` / `recordings_total`
  counters consistent.

### Multi-camera load (10 cameras, 320×180@10, motion + recording, no AI)

| Metric | Measured |
|---|---|
| Connected | 10/10 |
| Server CPU | 0.9 % |
| Server RSS | 14 MB |
| ffmpeg workers (10 rec + 10 analyzers) | 20 procs, 13.9 % CPU, 1.10 GB RSS |
| `errors_total`, `queue_pressure_total`, `db_errors_total` | 0, 0, 0 |

### AI load (5 cameras 640×360@15, 2 with AI sessions live)

| Metric | Measured |
|---|---|
| Server CPU incl. ONNX inference | ~25 % |
| Server RSS incl. ONNX session | ~133 MB |
| AI rate (2 cameras concurrent) | 3.33 infer/s total ≈ 1.67 FPS/camera |
| Inference latency | 86–92 ms (matches `benchmark` 87.7 ms) |

## Failure resilience (measured)

- Publisher killed: that camera → `connected: false`, `last_error`
  recorded, retry with backoff (500 ms base observed). Other cameras
  unaffected; server stays up.
- Full outage (all 5 sources + server-side RTSP broker down): all cameras
  offline, server healthy (`200`), 76 backoff retries logged, **no
  panics, no restarts**.
- Sources restored: all cameras reconnect automatically (5/5 within ~10 s).
- Recording survives AI/model absence (motion-only mode) — measured (server healthy, recordings continue).

## Honest AI capacity statement

The old spec target of "AI up to 10 FPS per camera" is **not achievable on
CPU-only** with YOLOv8n at 640² on this 2-vCPU host:

- Single isolated session: ~87.7 ms/inference → ~11 FPS sustained ceiling
  for one session on one core.
- With multiple cameras sharing the CPU, the sustained rate was **~1.7 FPS
  per camera** (recommended ceiling `ai.default_max_fps = 2.0`).
- The adaptive scheduler (idle 0.5 / motion 2 / active 5 fps gates) plus a
  ~0.05 ms motion pre-filter is what makes multi-camera CPU viable; most
  cameras idle at near-zero AI cost.
- **Plan for 1–2 FPS effective AI per camera on CPU-only, or use a
  GPU/VPU.** Do not claim higher numbers without measuring on the target
  hardware (see `docs/PERFORMANCE.md`).

## Capacity planning notes (extrapolated, clearly labelled)

- Copy/remux disk usage ≈ source bitrate (e.g. 720p30 ~0.6 MB/s/cam → 20
  cams ≈ 12 MB/s ≈ 1 TB/day — set `retention_days`).
- 20-camera CPU/RAM is extrapolated from the 10-camera run (~2× ffmpeg
  workers ≈ 2.2 GB RAM); not directly measured on this 2 GB box.
