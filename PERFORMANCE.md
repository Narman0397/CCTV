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

## Benchmark CLI

```bash
cctv-server benchmark                      # no model: reports AI SKIPPED
cctv-server benchmark --config /etc/cctv-server/config.toml   # with model if present
```

Exact outputs recorded in `docs/VERIFICATION-v1.0.2.md` and
`docs/BENCHMARKS.md`.
