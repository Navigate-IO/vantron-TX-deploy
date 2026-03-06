#!/bin/bash
# deploy.sh — Run on each Pi to install the MCS matrix test service.
#
# On the RX Pi:
#   sudo bash deploy.sh rx
#
# On the TX Pi:
#   sudo bash deploy.sh tx

set -euo pipefail

ROLE="${1:?Usage: sudo bash deploy.sh <tx|rx>}"
INSTALL_DIR="/opt/mcs-test"

echo "[deploy] Installing files to ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

# Copy scripts (assumes they're in the same directory as this deploy script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/tx_matrix.py"  "$INSTALL_DIR/"
cp "$SCRIPT_DIR/rx_control.py" "$INSTALL_DIR/"

# Copy sdmah-mesh.sh if it isn't already there
if [ ! -f "$INSTALL_DIR/sdmah-mesh.sh" ]; then
    # Try common locations
    for src in /home/*/sdmah-mesh.sh /home/*/BATMAN-Script/sdmah-mesh.sh /opt/BATMAN-Script/sdmah-mesh.sh; do
        if [ -f "$src" ]; then
            cp "$src" "$INSTALL_DIR/sdmah-mesh.sh"
            echo "[deploy] Copied sdmah-mesh.sh from $src"
            break
        fi
    done
fi

if [ ! -f "$INSTALL_DIR/sdmah-mesh.sh" ]; then
    echo "[deploy] WARNING: sdmah-mesh.sh not found. Place it in $INSTALL_DIR manually."
fi

chmod +x "$INSTALL_DIR"/*.py "$INSTALL_DIR"/*.sh 2>/dev/null || true

# Install the right systemd unit
if [ "$ROLE" = "tx" ]; then
    cp "$SCRIPT_DIR/mcs-matrix-tx.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable mcs-matrix-tx.service
    echo "[deploy] TX service installed and enabled."
    echo "[deploy] Edit IPs in /etc/systemd/system/mcs-matrix-tx.service then:"
    echo "           sudo systemctl daemon-reload"
    echo "           sudo systemctl start mcs-matrix-tx"
elif [ "$ROLE" = "rx" ]; then
    cp "$SCRIPT_DIR/mcs-matrix-rx.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable mcs-matrix-rx.service
    echo "[deploy] RX service installed and enabled."
    echo "[deploy] Edit IPs in /etc/systemd/system/mcs-matrix-rx.service then:"
    echo "           sudo systemctl daemon-reload"
    echo "           sudo systemctl start mcs-matrix-rx"
else
    echo "Unknown role '$ROLE'. Use 'tx' or 'rx'." >&2
    exit 1
fi

echo "[deploy] Done. Check logs with: journalctl -u mcs-matrix-${ROLE} -f"
