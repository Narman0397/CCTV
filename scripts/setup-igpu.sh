#!/usr/bin/env bash
# Enable Intel iGPU decode (VAAPI/QSV) for cctv-server on i5-8250U-class hosts.
#   sudo ./scripts/setup-igpu.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "ERROR: run as root" >&2; exit 1; }

say() { echo "==> $*"; }

if command -v apt-get >/dev/null 2>&1; then
  say "installing VAAPI / Intel media packages (best-effort)"
  apt-get install -y vainfo intel-gpu-tools \
    intel-media-va-driver-non-free 2>/dev/null \
    || apt-get install -y vainfo intel-media-va-driver 2>/dev/null \
    || echo "WARNING: install intel-media-va-driver manually" >&2
fi

getent group video >/dev/null 2>&1 && usermod -aG video cctv 2>/dev/null || true
getent group render >/dev/null 2>&1 && usermod -aG render cctv 2>/dev/null || true

if [[ -e /dev/dri/renderD128 ]]; then
  say "/dev/dri/renderD128 present"
else
  echo "WARNING: no /dev/dri/renderD128 — iGPU not exposed (VM/headless without GVT?)" >&2
fi

if command -v vainfo >/dev/null 2>&1; then
  say "vainfo (first lines)"
  vainfo 2>/dev/null | head -20 || true
else
  echo "WARNING: vainfo not installed" >&2
fi

FFMPEG="$(command -v ffmpeg || true)"
[[ -x /opt/cctv-server/bin/ffmpeg ]] && FFMPEG=/usr/bin/ffmpeg
if command -v ffmpeg >/dev/null 2>&1; then
  say "ffmpeg hwaccels:"
  ffmpeg -hide_banner -hwaccels 2>/dev/null || true
  echo "     Prefer distro ffmpeg with vaapi over a static 2018 build."
fi

mkdir -p /etc/systemd/system/cctv-server.service.d
if [[ -f /opt/cctv-server/lib/libonnxruntime.so ]]; then
  cat >/etc/systemd/system/cctv-server.service.d/ort.conf <<'EOF'
[Service]
Environment=ORT_DYLIB_PATH=/opt/cctv-server/lib/libonnxruntime.so
Environment=LD_LIBRARY_PATH=/opt/cctv-server/lib
EOF
  say "ORT drop-in written (found /opt/cctv-server/lib/libonnxruntime.so)"
else
  cat >/etc/systemd/system/cctv-server.service.d/ort.conf.example <<'EOF'
# Copy to ort.conf after placing a dylib that matches this binary's ort crate.
# Incompatible versions panic (BadVersion) — do not point at random 1.x wheels.
[Service]
Environment=ORT_DYLIB_PATH=/opt/cctv-server/lib/libonnxruntime.so
Environment=LD_LIBRARY_PATH=/opt/cctv-server/lib
EOF
  say "ORT example drop-in at /etc/systemd/system/cctv-server.service.d/ort.conf.example"
fi

systemctl daemon-reload
if systemctl is-enabled --quiet cctv-server 2>/dev/null; then
  systemctl restart cctv-server || true
fi
say "done. Re-login/restart so group video,render apply to the service."
