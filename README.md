# Models

The server ships **without** a model file. AI detection is optional: if no
model is present (or it cannot be loaded) the server runs in **motion-only
mode** — recording, events and the dashboard keep working. This is by
design.

## Where to put the model

The default location is `/opt/cctv-server/models/yolov8n.onnx` (set with
`[ai] model_dir` + `model_file` in the config).

## Get a model

Ultralytics publishes ready-to-use ONNX exports. Example (official
release asset):

```bash
sudo -u cctv cctv-server model install \
  https://github.com/ultralytics/assets/releases/download/v8.4.0/yolov8n.onnx
# or manually:
sudo curl -L -o /opt/cctv-server/models/yolov8n.onnx \
  https://github.com/ultralytics/assets/releases/download/v8.4.0/yolov8n.onnx
sudo systemctl restart cctv-server
```

You may use any YOLOv5/v8 ONNX export (640×640 input). The server does not
depend on a specific export tool — `model validate` verifies the file with
a real ONNX Runtime load test.

## Validate

```bash
cctv-server model list --config /etc/cctv-server/config.toml
cctv-server model validate --config /etc/cctv-server/config.toml \
  --model /opt/cctv-server/models/yolov8n.onnx
```

Output: `model`, `size`, `protobuf-header: ok`, `sha256`, `load-test:
ok (session loaded via ONNX Runtime)` → `result: OK`, exit 0.

If the ONNX Runtime shared library cannot be found:

```
load-test: FAILED (model error: ONNX Runtime library not found
(set ORT_DYLIB_PATH=/path/to/libonnxruntime.so))
```

Set `ORT_DYLIB_PATH` for the service (e.g. in the systemd unit
`Environment=`) or install onnxruntime so the loader finds it. The server
does **not** crash in this state — it just degrades to motion-only.

## Pin integrity (optional)

Set `model_sha256` in `[ai]` to pin the exact model file; `model validate`
then checks the SHA-256 and fails on mismatch (tamper protection).

## Expected CPU performance

YOLOv8n at 640×640 costs roughly **88 ms per inference** on a 2-core CPU
box (measured). The adaptive scheduler budgets 0.5–2.0 AI FPS per camera
by default, so a single CPU can serve several cameras — but do **not**
expect 10+ FPS per camera without a GPU (see `docs/PERFORMANCE.md`).
