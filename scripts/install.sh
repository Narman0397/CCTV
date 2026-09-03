#!/usr/bin/env bash
# =====================================================================
# cctv-server v1.0.2 — production installer for Ubuntu 22.04 / 24.04 x86_64
#
#   sudo ./scripts/install.sh
#
# Resolves the release layout from:
#   - packaged ZIP  ($RELEASE/{bin,web,config,systemd,docs,scripts})
#   - this repo     (same layout)
#   - flat dump     (files next to the script / parent)
# Never assumes a particular current working directory.
# =====================================================================
set -euo pipefail

APP_VERSION="1.0.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN="${CCTV_DRY_RUN:-0}"
BOOTSTRAP_FILE="/etc/cctv-server/.bootstrap-admin-password"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then echo "     [dry-run] $*"; return 0; fi
  "$@"
}

trap 'echo "ERROR: install failed at line $LINENO — re-run the installer to continue." >&2' ERR

[[ $EUID -eq 0 ]] || die "run as root (sudo ./scripts/install.sh)"

ARCH="$(uname -m)"
[[ "$ARCH" == "x86_64" ]] || die "unsupported architecture: $ARCH (this release targets x86_64)"

# v1.0.2 was linked with a GLIBC_2.39 verneed for two weak pidfd_* symbols.
# scripts/patch-glibc-compat.py drops that verneed so Ubuntu 22.04 / Debian 12 run.
if [[ -f "$RELEASE_DIR/scripts/patch-glibc-compat.py" ]]; then
  python3 "$RELEASE_DIR/scripts/patch-glibc-compat.py" "$RELEASE_DIR/bin/cctv-server" || true
fi

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VER="${VERSION_ID:-unknown}"
  if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    die "unsupported OS: ${PRETTY_NAME:-$OS_ID} (this installer targets Ubuntu/Debian)"
  fi
  case "$OS_VER" in
    24.04|13) : ;;
    22.04|12)
      echo "WARNING: OS ${PRETTY_NAME:-$OS_ID $OS_VER} is below the glibc 2.39 floor of this binary. Install will abort at the libc check." >&2
      ;;
    *) echo "WARNING: primary target is Ubuntu 24.04 / Debian 13 x86_64; you are on ${PRETTY_NAME:-$OS_ID $OS_VER}." >&2 ;;
  esac
else
  die "cannot detect OS (/etc/os-release missing)"
fi

# ---- 1. resolve release layout --------------------------------------
BIN_SRC="" WEB_SRC="" CFG_SRC="" UNIT_SRC="" DOCS_SRC=""
for cand in \
  "$RELEASE_DIR/bin/cctv-server" \
  "$SCRIPT_DIR/../bin/cctv-server" \
  "$SCRIPT_DIR/cctv-server" \
  "$RELEASE_DIR/cctv-server"
do
  [[ -f "$cand" && -x "$cand" ]] && { BIN_SRC="$cand"; break; }
done
for cand in \
  "$RELEASE_DIR/web/index.html" \
  "$SCRIPT_DIR/index.html" \
  "$RELEASE_DIR/index.html"
do
  [[ -f "$cand" ]] && { WEB_SRC="$cand"; break; }
done
for cand in \
  "$RELEASE_DIR/config/config.example.toml" \
  "$RELEASE_DIR/config/config.toml" \
  "$SCRIPT_DIR/config.example.toml" \
  "$RELEASE_DIR/config.example.toml" \
  "$SCRIPT_DIR/config.toml"
do
  [[ -f "$cand" ]] && { CFG_SRC="$cand"; break; }
done
for cand in \
  "$RELEASE_DIR/systemd/cctv-server.service" \
  "$SCRIPT_DIR/cctv-server.service" \
  "$RELEASE_DIR/cctv-server.service"
do
  [[ -f "$cand" ]] && { UNIT_SRC="$cand"; break; }
done
for cand in "$RELEASE_DIR/docs" "$SCRIPT_DIR/../docs"; do
  if [[ -d "$cand" && -f "$cand/ARCHITECTURE.md" ]]; then DOCS_SRC="$cand"; break; fi
done
# flat GitHub dump: markdown files live next to the binary
if [[ -z "$DOCS_SRC" && -f "$RELEASE_DIR/ARCHITECTURE.md" ]]; then
  DOCS_SRC="$RELEASE_DIR"
fi

[[ -n "$BIN_SRC" ]] || die "cctv-server binary not found (looked in $RELEASE_DIR/bin and $SCRIPT_DIR)"
[[ -n "$WEB_SRC" ]] || die "web dashboard not found"
[[ -n "$CFG_SRC" ]] || die "config template not found"
[[ -n "$UNIT_SRC" ]] || die "systemd unit not found"
say "release layout: $(dirname "$BIN_SRC")"

if ! command -v ffmpeg >/dev/null 2>&1 && [[ ! -x "$RELEASE_DIR/bin/ffmpeg" ]]; then
  say "ffmpeg not on PATH — downloading a static build (npm @ffmpeg-installer/linux-x64)"
  FF_TMP="$(mktemp -d)"
  if curl -fsSL "https://registry.npmjs.org/@ffmpeg-installer/linux-x64/-/linux-x64-4.1.0.tgz" -o "$FF_TMP/ff.tgz"; then
    tar -xzf "$FF_TMP/ff.tgz" -C "$FF_TMP"
    if [[ -f "$FF_TMP/package/ffmpeg" ]]; then
      install -m 0755 "$FF_TMP/package/ffmpeg" "$RELEASE_DIR/bin/ffmpeg"
    fi
  fi
  rm -rf "$FF_TMP"
  [[ -x "$RELEASE_DIR/bin/ffmpeg" ]] || die "ffmpeg is required (sudo apt install ffmpeg)"
fi
command -v curl >/dev/null 2>&1 || echo "WARNING: curl not found (needed for readiness check and remote model install)" >&2

if ! getent group cctv >/dev/null 2>&1; then
  say "creating group cctv"
  run groupadd --system cctv
fi
if ! getent passwd cctv >/dev/null 2>&1; then
  say "creating system user cctv (no shell, no login)"
  run useradd --system --gid cctv --home-dir /var/lib/cctv-server \
      --shell /usr/sbin/nologin --comment "cctv-server service user" cctv
fi
getent group video >/dev/null 2>&1 && run usermod -aG video cctv || true
getent group render >/dev/null 2>&1 && run usermod -aG render cctv || true

say "creating directories"
run install -d -m 0755 -o root -g cctv /opt/cctv-server/bin /opt/cctv-server/web \
                  /opt/cctv-server/models /opt/cctv-server/migrations /opt/cctv-server/docs
run install -d -m 0750 -o root -g cctv /etc/cctv-server
run install -d -m 0750 -o cctv -g cctv /var/lib/cctv-server/database /var/lib/cctv-server/recordings \
                  /var/lib/cctv-server/snapshots /var/lib/cctv-server/events \
                  /var/lib/cctv-server/state
run install -d -m 0750 -o cctv -g cctv /var/log/cctv-server

say "installing binary"
run install -m 0755 -o root -g cctv "$BIN_SRC" /opt/cctv-server/bin/cctv-server
if [[ -x "$RELEASE_DIR/scripts/patch-glibc-compat.py" ]]; then
  run python3 "$RELEASE_DIR/scripts/patch-glibc-compat.py" /opt/cctv-server/bin/cctv-server || true
fi
if [[ -x "$RELEASE_DIR/bin/ffmpeg" ]]; then
  say "installing bundled ffmpeg"
  run install -m 0755 -o root -g cctv "$RELEASE_DIR/bin/ffmpeg" /opt/cctv-server/bin/ffmpeg
fi
if [[ -f "$RELEASE_DIR/models/yolov8n.onnx" ]]; then
  say "installing YOLO model"
  run install -m 0644 -o root -g cctv "$RELEASE_DIR/models/yolov8n.onnx" /opt/cctv-server/models/yolov8n.onnx
fi
say "installing web dashboard"
run install -m 0644 -o root -g cctv "$WEB_SRC" /opt/cctv-server/web/index.html
if [[ -n "$DOCS_SRC" && -d "$DOCS_SRC" ]]; then
  say "installing documentation"
  run rm -rf /opt/cctv-server/docs
  run mkdir -p /opt/cctv-server/docs
  run find "$DOCS_SRC" -maxdepth 1 -type f -name '*.md' -exec cp -a {} /opt/cctv-server/docs/ \;
  if [[ -f "$RELEASE_DIR/README.md" ]]; then
    run install -m 0644 -o root -g cctv "$RELEASE_DIR/README.md" /opt/cctv-server/docs/README.md
  fi
  run chown -R root:cctv /opt/cctv-server/docs
  run find /opt/cctv-server/docs -type f -exec chmod 0644 {} +
  run find /opt/cctv-server/docs -type d -exec chmod 0755 {} +
fi
if [[ -f "$RELEASE_DIR/models/README.md" ]]; then
  run install -m 0644 -o root -g cctv "$RELEASE_DIR/models/README.md" /opt/cctv-server/models/README.md
fi
say "installing VERSION / integrity files"
printf '%s\n' "$APP_VERSION" | run tee /opt/cctv-server/VERSION >/dev/null
if [[ -f "$RELEASE_DIR/RELEASE-MANIFEST.json" ]]; then
  run install -m 0644 -o root -g cctv "$RELEASE_DIR/RELEASE-MANIFEST.json" /opt/cctv-server/RELEASE-MANIFEST.json
fi
if [[ -f "$RELEASE_DIR/SHA256SUMS" ]]; then
  run install -m 0644 -o root -g cctv "$RELEASE_DIR/SHA256SUMS" /opt/cctv-server/SHA256SUMS
fi

say "installing configuration"
if [[ -f /etc/cctv-server/config.toml ]]; then
  cp -a /etc/cctv-server/config.toml "/etc/cctv-server/config.toml.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  echo "     existing config kept (backup created)"
else
  run install -m 0640 -o root -g cctv "$CFG_SRC" /etc/cctv-server/config.toml
fi
run install -d -m 0755 -o root -g cctv /opt/cctv-server/config
if [[ -f "$RELEASE_DIR/config/config.example.toml" ]]; then
  run install -m 0644 -o root -g cctv "$RELEASE_DIR/config/config.example.toml" /opt/cctv-server/config/config.example.toml
fi
if [[ -f "$RELEASE_DIR/config/profile-i5-8gb.toml" ]]; then
  run install -m 0644 -o root -g cctv "$RELEASE_DIR/config/profile-i5-8gb.toml" /opt/cctv-server/config/profile-i5-8gb.toml
fi
if [[ -f "$RELEASE_DIR/scripts/setup-igpu.sh" ]]; then
  run install -m 0755 -o root -g cctv "$RELEASE_DIR/scripts/setup-igpu.sh" /opt/cctv-server/bin/setup-igpu.sh
fi

say "preparing secrets file"
SECRETS=/etc/cctv-server/secrets.env
if [[ ! -f "$SECRETS" ]]; then
  {
    echo "# cctv-server secrets — generated at install time, mode 0600"
    echo "# No secret is required at runtime: sessions are opaque server-side"
    echo "# tokens and passwords are Argon2id-hashed in the database."
    echo "# (legacy JWT_SECRET entries are ignored for forward compatibility)"
  } | run tee "$SECRETS" >/dev/null
fi
run chmod 0600 "$SECRETS"
run chown root:root "$SECRETS"

say "installing systemd unit"
run install -m 0644 -o root -g root "$UNIT_SRC" /etc/systemd/system/cctv-server.service
run systemctl daemon-reload

say "environment pre-flight (ffmpeg, directories, database)"
if [[ "$DRY_RUN" != "1" ]]; then
  if ! /opt/cctv-server/bin/cctv-server env-guard --config /etc/cctv-server/config.toml; then
    echo "ERROR: environment pre-flight failed — fix the reported issue and re-run." >&2
    exit 1
  fi
fi

say "initializing database (first-run admin password is generated once)"
ADMIN_PW=""
if [[ "$DRY_RUN" == "1" ]]; then
  run /opt/cctv-server/bin/cctv-server init --config /etc/cctv-server/config.toml --password-file "$BOOTSTRAP_FILE"
else
  rm -f "$BOOTSTRAP_FILE"
  umask 077
  if ! /opt/cctv-server/bin/cctv-server init --config /etc/cctv-server/config.toml --password-file "$BOOTSTRAP_FILE"; then
    echo "ERROR: init failed" >&2
    exit 1
  fi
  if [[ -f "$BOOTSTRAP_FILE" ]]; then
    ADMIN_PW="$(sed -n 's/^CCTV_ADMIN_PASSWORD=//p' "$BOOTSTRAP_FILE" | head -1)"
  fi
fi

say "setting data ownership"
run chown -R cctv:cctv /var/lib/cctv-server
run chown cctv:cctv /var/log/cctv-server

say "enabling and starting service"
run systemctl enable cctv-server
run systemctl start cctv-server || {
  echo "ERROR: service failed to start — check: journalctl -u cctv-server -n 50" >&2
  exit 1
}

say "waiting for readiness (/api/ready)"
OK=0
if command -v curl >/dev/null 2>&1; then
  for _i in $(seq 1 45); do
    if curl -fsS --max-time 2 http://127.0.0.1:8080/api/ready >/dev/null 2>&1; then
      OK=1; break
    fi
    if ! systemctl is-active --quiet cctv-server; then
      echo "ERROR: service died while waiting for readiness — check: journalctl -u cctv-server -n 50" >&2
      exit 1
    fi
    sleep 1
  done
else
  echo "WARNING: curl missing — skipping HTTP readiness (service is active)." >&2
  systemctl is-active --quiet cctv-server && OK=1
fi
if [[ "$OK" != "1" ]]; then
  echo "ERROR: service did not become ready within 45s (last logs below):" >&2
  journalctl -u cctv-server -n 20 --no-pager >&2 || true
  exit 1
fi
say "readiness passed"

DASH_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$DASH_HOST" ]] || DASH_HOST="127.0.0.1"

echo
echo "============================================================"
echo "  cctv-server $APP_VERSION installed successfully."
echo "  dashboard: http://${DASH_HOST}:8080"
echo "  local:     http://127.0.0.1:8080"
echo "  status:    systemctl status cctv-server"
echo "  logs:      journalctl -u cctv-server -f"
if [[ -n "$ADMIN_PW" ]]; then
  echo
  echo "  >>> FIRST-RUN ADMIN PASSWORD (shown once):"
  echo "  >>>   user: admin"
  echo "  >>>   pass: $ADMIN_PW"
  echo "  >>> CHANGE IT IMMEDIATELY after first login."
  rm -f "$BOOTSTRAP_FILE" 2>/dev/null || true
else
  echo "  admin password: already set (reinstall) or supplied via CCTV_ADMIN_PASSWORD."
fi
echo "============================================================"
echo
echo "Models: put yolov8n.onnx into /opt/cctv-server/models/ and restart,"
echo "        or: cctv-server model install <url> && systemctl restart cctv-server"
