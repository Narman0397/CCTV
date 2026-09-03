#!/usr/bin/env bash
# =====================================================================
# cctv-server v1.0.2 — transactional upgrade helper
#
#   sudo ./scripts/upgrade.sh /path/to/new/release.zip
# =====================================================================
set -euo pipefail

APP_VERSION="1.0.2"
STAMP="$(date +%Y%m%d%H%M%S)"
BK="/var/backups/cctv-server-$STAMP"
STATE_FILE="$BK/upgrade-state"
DB_BACKUP=""
TMP=""

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root (sudo ./scripts/upgrade.sh <zip>)" >&2; exit 1; }

ZIP="${1:-}"
if [[ -z "$ZIP" ]]; then
  echo "usage: sudo $0 /path/to/cctv-ai-server-<ver>-linux-x86_64.zip" >&2
  exit 1
fi
[[ -f "$ZIP" ]] || { echo "ERROR: $ZIP not found" >&2; exit 1; }

BIN=/opt/cctv-server/bin/cctv-server
CFG=/etc/cctv-server/config.toml
SECRETS=/etc/cctv-server/secrets.env
DB_DIR=/var/lib/cctv-server/database
UNIT=/etc/systemd/system/cctv-server.service
READY_URL=http://127.0.0.1:8080/api/ready

echo "==> cctv-server upgrade to $APP_VERSION from $ZIP"

note() { mkdir -p "$BK"; echo "$1" >> "$STATE_FILE"; }

version_gt() {
  # return 0 if $1 > $2
  local a="$1" b="$2"
  [[ "$a" == "$b" ]] && return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$a" "$b" <<'PY'
import sys
def parts(s):
    out=[]
    for p in s.replace("-", ".").split("."):
        try: out.append(int(p))
        except ValueError: break
    return out or [0]
x, y = parts(sys.argv[1]), parts(sys.argv[2])
n=max(len(x),len(y)); x+=[0]*(n-len(x)); y+=[0]*(n-len(y))
sys.exit(0 if x>y else 1)
PY
    return $?
  fi
  [[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | tail -1)" == "$a" ]]
}

rollback() {
  echo "==> ROLLBACK: restoring previous release artifacts" >&2
  systemctl stop cctv-server 2>/dev/null || true
  if [[ -f "$BK/cctv-server.bak" ]]; then install -m 0755 -o root -g cctv "$BK/cctv-server.bak" /opt/cctv-server/bin/cctv-server; fi
  if [[ -f "$BK/config.toml" ]]; then install -m 0640 -o root -g cctv "$BK/config.toml" "$CFG"; fi
  if [[ -f "$BK/secrets.env" ]]; then install -m 0600 -o root -g root "$BK/secrets.env" "$SECRETS"; fi
  if [[ -f "$BK/cctv-server.service" ]]; then install -m 0644 -o root -g root "$BK/cctv-server.service" "$UNIT"; fi
  if [[ -f "$BK/VERSION.old" ]]; then install -m 0644 -o root -g cctv "$BK/VERSION.old" /opt/cctv-server/VERSION; fi
  if [[ -f "$BK/RELEASE-MANIFEST.json.old" ]]; then
    install -m 0644 -o root -g cctv "$BK/RELEASE-MANIFEST.json.old" /opt/cctv-server/RELEASE-MANIFEST.json
  fi
  if [[ -f "$BK/SHA256SUMS.old" ]]; then
    install -m 0644 -o root -g cctv "$BK/SHA256SUMS.old" /opt/cctv-server/SHA256SUMS
  fi
  if [[ -d "$BK/web" ]]; then rm -rf /opt/cctv-server/web && cp -a "$BK/web" /opt/cctv-server/web; fi
  if [[ -d "$BK/docs" ]]; then rm -rf /opt/cctv-server/docs && cp -a "$BK/docs" /opt/cctv-server/docs; fi
  DB_FILE="$DB_DIR/cctv.db"
  if [[ -n "$DB_BACKUP" && -f "$DB_BACKUP" ]]; then
    echo "     restoring database backup (consistent snapshot)" >&2
    install -m 0640 -o cctv -g cctv "$DB_BACKUP" "$DB_FILE"
  fi
  chown -R cctv:cctv /var/lib/cctv-server 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  systemctl start cctv-server 2>/dev/null || true
  echo "Rollback complete. Previous version is running again." >&2
  [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"
  exit 1
}

echo "==> [1/12] verifying running installation"
if [[ ! -x "$BIN" ]]; then
  echo "ERROR: no existing installation at $BIN — use scripts/install.sh for a fresh install." >&2
  exit 1
fi
if systemctl is-active --quiet cctv-server 2>/dev/null; then
  echo "     service is running ($("$BIN" --version 2>/dev/null || echo unknown))"
else
  echo "     WARNING: cctv-server service is not active — will still upgrade files." >&2
fi
"$BIN" db info --config "$CFG" >/dev/null 2>&1 || { echo "ERROR: existing database cannot be opened." >&2; exit 1; }

echo "==> [2/12] verifying package integrity (SHA256SUMS)"
TMP="$(mktemp -d)"
unzip -q "$ZIP" -d "$TMP"
NEW_ROOT="$(find "$TMP" -maxdepth 3 -name RELEASE-MANIFEST.json -printf '%h\n' 2>/dev/null | head -1)"
[[ -z "$NEW_ROOT" ]] && NEW_ROOT="$TMP"
cd "$NEW_ROOT"
if [[ -f SHA256SUMS ]]; then
  if ! sha256sum -c SHA256SUMS; then
    echo "ERROR: SHA256SUMS verification failed." >&2
    rm -rf "$TMP"; exit 1
  fi
else
  echo "ERROR: SHA256SUMS missing from release." >&2
  rm -rf "$TMP"; exit 1
fi
NEW_BIN="$NEW_ROOT/bin/cctv-server"
[[ -f "$NEW_BIN" && -x "$NEW_BIN" ]] || { echo "ERROR: no bin/cctv-server in $ZIP" >&2; rm -rf "$TMP"; exit 1; }

echo "==> [3/12] checking version and architecture"
NEW_VER="$("$NEW_BIN" --version 2>/dev/null | awk '{print $2}')"
CUR_VER="$("$BIN" --version 2>/dev/null | awk '{print $2}')"
ARCH="$(uname -m)"
[[ "$ARCH" == "x86_64" ]] || { echo "ERROR: unsupported architecture $ARCH" >&2; rm -rf "$TMP"; exit 1; }
if ! "$NEW_BIN" --version >/dev/null 2>&1; then
  echo "ERROR: new binary cannot execute on this host (typically GLIBC_2.39 missing — need Ubuntu 24.04 / Debian 13)." >&2
  rm -rf "$TMP"; exit 1
fi
if [[ -n "$CUR_VER" && -n "$NEW_VER" ]] && version_gt "$CUR_VER" "$NEW_VER"; then
  echo "ERROR: downgrade $CUR_VER → $NEW_VER is refused (schema may have moved forward)." >&2
  echo "       Restore from /var/backups/cctv-server-*/ and the old release ZIP instead." >&2
  rm -rf "$TMP"; exit 1
fi
echo "     new version: ${NEW_VER:-unknown} (arch $ARCH) current: ${CUR_VER:-unknown}"

command -v ffmpeg >/dev/null 2>&1 || { echo "ERROR: ffmpeg missing (required)." >&2; rm -rf "$TMP"; exit 1; }

echo "==> [4/12] environment pre-flight"
"$NEW_BIN" env-guard --config "$CFG" || { echo "ERROR: env-guard failed with new binary." >&2; rm -rf "$TMP"; exit 1; }

echo "==> [5/12] stopping service and creating consistent backups"
systemctl stop cctv-server 2>/dev/null || true
mkdir -p "$BK"
note "backup-dir: $BK"

if [[ -f "$CFG" ]]; then cp -a "$CFG" "$BK/config.toml"; fi
if [[ -f "$SECRETS" ]]; then cp -a "$SECRETS" "$BK/secrets.env"; fi
[[ -f "$BIN" ]] && cp -a "$BIN" "$BK/cctv-server.bak"
if [[ -f "$UNIT" ]]; then cp -a "$UNIT" "$BK/cctv-server.service"; fi
if [[ -f /opt/cctv-server/VERSION ]]; then cp -a /opt/cctv-server/VERSION "$BK/VERSION.old"; fi
if [[ -f /opt/cctv-server/RELEASE-MANIFEST.json ]]; then
  cp -a /opt/cctv-server/RELEASE-MANIFEST.json "$BK/RELEASE-MANIFEST.json.old"
fi
if [[ -f /opt/cctv-server/SHA256SUMS ]]; then cp -a /opt/cctv-server/SHA256SUMS "$BK/SHA256SUMS.old"; fi
if [[ -d /opt/cctv-server/web ]]; then cp -a /opt/cctv-server/web "$BK/web"; fi
if [[ -d /opt/cctv-server/docs ]]; then cp -a /opt/cctv-server/docs "$BK/docs"; fi

DB_FILE="$DB_DIR/cctv.db"
DB_BACKUP="$BK/cctv.db.consistent"
if [[ -f "$DB_FILE" ]]; then
  echo "     backing up database with SQLite Online Backup API (consistent snapshot)"
  if ! "$BIN" db backup --config "$CFG" "$DB_BACKUP" >/dev/null 2>&1; then
    echo "ERROR: could not create consistent database backup with the CURRENT binary." >&2
    systemctl start cctv-server 2>/dev/null || true
    rm -rf "$TMP"; exit 1
  fi
  note "db-backup: $DB_BACKUP"
else
  echo "     (no database file present; skipping DB backup)"
  DB_BACKUP=""
fi

trap rollback ERR

echo "==> [6/12] replacing release artifacts"
install -m 0755 -o root -g cctv "$NEW_BIN" /opt/cctv-server/bin/cctv-server
if [[ -f "$NEW_ROOT/web/index.html" ]]; then
  rm -rf /opt/cctv-server/web && mkdir -p /opt/cctv-server/web
  install -m 0644 -o root -g cctv "$NEW_ROOT/web/index.html" /opt/cctv-server/web/index.html
fi
if [[ -f "$NEW_ROOT/systemd/cctv-server.service" ]]; then
  install -m 0644 -o root -g root "$NEW_ROOT/systemd/cctv-server.service" "$UNIT"
  systemctl daemon-reload
fi
if [[ -f "$NEW_ROOT/config/config.example.toml" ]]; then
  mkdir -p /opt/cctv-server/config
  install -m 0644 -o root -g cctv "$NEW_ROOT/config/config.example.toml" /opt/cctv-server/config/config.example.toml
fi
if [[ -f "$NEW_ROOT/config/profile-i5-8gb.toml" ]]; then
  mkdir -p /opt/cctv-server/config
  install -m 0644 -o root -g cctv "$NEW_ROOT/config/profile-i5-8gb.toml" /opt/cctv-server/config/profile-i5-8gb.toml
fi
if [[ -f "$NEW_ROOT/scripts/setup-igpu.sh" ]]; then
  install -m 0755 -o root -g cctv "$NEW_ROOT/scripts/setup-igpu.sh" /opt/cctv-server/bin/setup-igpu.sh
fi
if [[ -f "$NEW_ROOT/VERSION" ]]; then
  install -m 0644 -o root -g cctv "$NEW_ROOT/VERSION" /opt/cctv-server/VERSION
fi
if [[ -f "$NEW_ROOT/RELEASE-MANIFEST.json" ]]; then
  install -m 0644 -o root -g cctv "$NEW_ROOT/RELEASE-MANIFEST.json" /opt/cctv-server/RELEASE-MANIFEST.json
fi
if [[ -f "$NEW_ROOT/SHA256SUMS" ]]; then
  install -m 0644 -o root -g cctv "$NEW_ROOT/SHA256SUMS" /opt/cctv-server/SHA256SUMS
fi
if [[ -d "$NEW_ROOT/docs" ]]; then
  rm -rf /opt/cctv-server/docs && cp -a "$NEW_ROOT/docs" /opt/cctv-server/docs
  if [[ -f "$NEW_ROOT/README.md" ]]; then
    install -m 0644 -o root -g cctv "$NEW_ROOT/README.md" /opt/cctv-server/docs/README.md
  fi
  chown -R root:cctv /opt/cctv-server/docs
  find /opt/cctv-server/docs -type f -exec chmod 0644 {} +
  find /opt/cctv-server/docs -type d -exec chmod 0755 {} +
fi
if [[ -d "$NEW_ROOT/models" ]]; then
  mkdir -p /opt/cctv-server/models
  cp -n "$NEW_ROOT"/models/* /opt/cctv-server/models/ 2>/dev/null || true
fi

echo "==> [7/12] running migrations / init"
if ! "$BIN" init --config "$CFG"; then
  echo "ERROR: init/migration failed" >&2
  rollback
fi
chown -R cctv:cctv /var/lib/cctv-server
echo "     (note: an existing admin is left untouched — init is idempotent)"

echo "==> [8/12] validating configuration and database"
"$BIN" health --config "$CFG" >/dev/null
"$BIN" db integrity --config "$CFG" | sed 's/^/     /'

echo "==> [9/12] starting service and waiting for readiness"
systemctl start cctv-server
OK=0
for _i in $(seq 1 45); do
  if curl -fsS --max-time 2 "$READY_URL" >/dev/null 2>&1; then OK=1; break; fi
  if ! systemctl is-active --quiet cctv-server; then break; fi
  sleep 1
done
[[ "$OK" == "1" ]] || { echo "ERROR: readiness not reached" >&2; rollback; }

echo "==> [10/12] smoke checks"
HEALTH="$(curl -fsS --max-time 3 http://127.0.0.1:8080/api/health)" || { echo "ERROR: health failed" >&2; rollback; }
echo "     health: $(printf '%s' "$HEALTH" | head -c 200)"
READY="$(curl -fsS --max-time 3 "$READY_URL")" || { echo "ERROR: ready failed" >&2; rollback; }
echo "     ready: $(printf '%s' "$READY" | head -c 200)"

echo "==> [11/12] upgrade marked successful"
note "status: success"
echo
echo "============================================================"
echo "  Upgrade complete."
echo "  New version: $("$BIN" --version)"
echo "  Backup kept at: $BK"
echo "============================================================"
trap - ERR
rm -rf "$TMP"
