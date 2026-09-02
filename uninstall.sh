#!/usr/bin/env bash
# =====================================================================
# cctv-server v1.0.2 — uninstaller
#
#   sudo ./scripts/uninstall.sh            # remove app+config, KEEP data
#   sudo ./scripts/uninstall.sh --purge    # remove app+config+data (destructive)
#
# Recordings are NEVER removed without an explicit --purge confirmation.
# =====================================================================
set -euo pipefail

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root (sudo ./scripts/uninstall.sh)" >&2; exit 1; }

if [[ "$PURGE" == "1" ]]; then
  echo "WARNING: --purge will DELETE all recordings, snapshots, database and logs."
  read -r -p "Type 'PURGE' to confirm: " CONFIRM
  [[ "$CONFIRM" == "PURGE" ]] || { echo "aborted."; exit 1; }
fi

echo "==> Stopping and disabling service"
systemctl disable --now cctv-server 2>/dev/null || true
rm -f /etc/systemd/system/cctv-server.service
systemctl daemon-reload 2>/dev/null || true

echo "==> Removing program files"
rm -rf /opt/cctv-server
rm -f /etc/cctv-server/config.toml
rm -f /etc/cctv-server/secrets.env
rmdir /etc/cctv-server 2>/dev/null || true

if [[ "$PURGE" == "1" ]]; then
  echo "==> Removing service user and data"
  userdel cctv 2>/dev/null || true
  groupdel cctv 2>/dev/null || true
  rm -rf /var/lib/cctv-server /var/log/cctv-server
else
  echo "==> Keeping data:"
  echo "    /var/lib/cctv-server  (recordings, snapshots, database)"
  echo "    /var/log/cctv-server  (logs)"
  echo "    Use uninstall.sh --purge to remove them too."
fi

echo "cctv-server removed."
