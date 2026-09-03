# Performance & capacity — v1.0.2

All numbers below are **measured on this release's reference host**
(2 vCPU x86_64 Debian 13 sandbox, no GPU, NVMe workspace disk) by the
built-in `cctv-server benchmark` (binary runs a real 720p frame through
the actual motion/jpeg/copy/disk paths; AI numbers come from a real
ONNX Runtime YOLOv8n session). They are guidance, not vendor claims.
**Measure on your own hardware.**

## Measured single-frame costs (720p)

| Operation | Result |
|---|---|
| motion pre-filter (160×90 luma diff) | 0.05–0.06 ms/frame |
| frame copy + ring-arc store | 0.22–0.23 ms/frame |
| JPEG encode 720p q80 | ~48–52 ms/frame (~1.26 MB) |
| disk write throughput (host) | ~2.5–2.7 GB/s |
| YOLOv8n 640×640 CPU inference | 83–88 ms/inference |
| max sustained CPU AI FPS (this host) | ~12 FPS aggregate |

## System loads measured

- 10 cameras 320×180@10 motion+recording, AI disabled: server process
  ~0.9% CPU, ~14 MB RSS; total RSS dominated by ffmpeg workers
  (~55 MB each → ~1.1 GB for 20 workers on 2 cameras; per-worker
  ~55 MB observed).
- AI concurrent with recording: keep the AI per-camera FPS budget ≤ 2.0
  (default) on CPU; the adaptive scheduler (idle/motion/active tiers)
  protects recordings and UI under load.
- Bounded queues: under sustained load the AI queue pressure stayed 0
  (frames skipped, not queued unboundedly).

## Planning guidance

- **Per-camera ingest budget**: one server process handles ~100–200
  low-res motion+capture streams easily; real cost is ffmpeg worker
  RSS and disk I/O.
- **CPU AI**: expect roughly 1–2 FPS per camera when several cameras run
  AI simultaneously on 2 cores; enable AI only on cameras where it adds
  value, or add a GPU (config `[hardware] acceleration`).
- **Disk**: recordings are remuxed MP4s ≈ source bitrate. A 1080p @
  8 Mb/s camera ≈ 3.6 GB/hour. Use `retention_days` and monitor
  `/api/storage`.
- **RAM**: 1 GB minimum; 2–4 GB recommended for AI + 4–8 cameras.

## Profile: Intel Core i5 + 8 GB RAM (CPU-only)

Shipped defaults (`config/config.example.toml`) and
`config/profile-i5-8gb.toml` target this box. YOLOv8n @ 640 is ~85 ms
on a 2-core host (~12 AI FPS aggregate). An i5 (4–6 cores) typically
sustains **~18–28 aggregate AI FPS**, not 25 FPS per camera.

| Goal | Cameras | AI |
|---|---|---|
| Maximum useful detection | **4** | all on, 1.5–2 FPS, 720p record |
| Aggressive | **6** | 1 FPS or `input_size = 320` |
| Coverage | **8–10** | AI on 2–4 priority cameras only |

Practices that actually raise effectiveness on this SKU:

1. Point the analyzer at a **substream** (640×360 / 720p@15), keep
   high-res only for recording if the camera exposes two URLs.
2. Keep `preview_fps` at 3–5; `active_fps` at 2 (not 5).
3. Leave `[hardware] acceleration = "auto"` (QSV/VAAPI) when Intel
   iGPU drivers are installed — this is the real multiplier, not a
   Rust rewrite.
4. Watch `/api/system` (CPU &lt; 75%, RAM &lt; 80%) and
   `frames_dropped` on `/api/metrics`.

## i5-8250U + 8 GB (FFmpeg VAAPI + nano@320)

This SKU is 15 W / UHD 620. Shipped defaults now use `input_size = 320`,
`active_fps = 1.5`, `preview_fps = 4`. After install:

```bash
sudo /opt/cctv-server/bin/setup-igpu.sh    # groups, vainfo, ffmpeg hwaccels
sudo apt install -y ffmpeg intel-media-va-driver-non-free   # VAAPI-capable ffmpeg
# cameras: RTSP substream only
curl -s http://127.0.0.1:8080/api/health    # ai_model_loaded
sudo intel_gpu_top                          # Video engine should move
```

OpenVINO on the iGPU needs a **matching** `libonnxruntime.so` plus the
OpenVINO EP next to it. Point systemd at it only after `model validate`
succeeds — a wrong wheel panics (`BadVersion`). Example drop-in:
`/etc/systemd/system/cctv-server.service.d/ort.conf.example`
(written by `setup-igpu.sh`).

## Benchmark CLI

```bash
cctv-server benchmark                      # no model: reports AI SKIPPED
cctv-server benchmark --config /etc/cctv-server/config.toml   # with model if present
```

Exact outputs recorded in `docs/VERIFICATION-v1.0.2.md` and
`docs/BENCHMARKS.md`.
