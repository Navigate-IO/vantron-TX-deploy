#!/bin/bash
# deploy.sh for TX Pi
#
# This is the ONLY script you need to run on a fresh Pi.
# It runs the install script (clones repos, builds driver, loads modules),
# then sets up the MCS test systemd service.
#
# Usage:
#   git clone https://github.com/Navigate-IO/TX-deploy.git
#   cd TX-deploy
#   sudo bash deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/mcs-test"

# Paths that install-script.sh will create
INSTALL_SCRIPT_REPO="/home/pi/install-script"
DRIVER_DIR="/home/pi/morse_driver"
BATMAN_DIR="/home/pi/BATMAN-Script"
MCS_TEST_DIR="/home/pi/Recieve-Transfer-MCS-Test"

echo "============================================"
echo " MCS Matrix TX — Full Setup"
echo "============================================"

# -----------------------------------------------------------
# 1. Clone and run the install script (driver + repos)
# -----------------------------------------------------------
echo ""
echo "[1/4] Running install script (driver build + repo clones)..."

if [ -d "$INSTALL_SCRIPT_REPO" ]; then
    echo "  → install-script repo exists, pulling latest..."
    git -C "$INSTALL_SCRIPT_REPO" pull
else
    git clone https://github.com/Navigate-IO/install-script.git "$INSTALL_SCRIPT_REPO"
fi

bash "$INSTALL_SCRIPT_REPO/install-script.sh"

# -----------------------------------------------------------
# 2. Verify repos were cloned by install script
# -----------------------------------------------------------
echo ""
echo "[2/4] Verifying dependencies..."

for dir in "$MCS_TEST_DIR" "$BATMAN_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "ERROR: Expected $dir to exist after install script. Something went wrong."
        exit 1
    fi
done
echo "  All repos present."

# -----------------------------------------------------------
# 3. Install MCS test files to /opt/mcs-test
# -----------------------------------------------------------
echo ""
echo "[3/4] Installing MCS test files to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"

cp "$MCS_TEST_DIR/tx_matrix.py"     "$INSTALL_DIR/"
cp "$MCS_TEST_DIR/rx_control.py"    "$INSTALL_DIR/"
cp "$BATMAN_DIR/sdmah-mesh.sh"      "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR"/*.py "$INSTALL_DIR"/*.sh 2>/dev/null || true

# -----------------------------------------------------------
# 4. Install systemd service
# -----------------------------------------------------------
echo ""
echo "[4/4] Installing systemd service..."
cp "$SCRIPT_DIR/mcs-matrix-tx.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable mcs-matrix-tx.service

echo ""
echo "============================================"
echo " TX setup complete!"
echo "============================================"
echo ""
echo " Driver:  built and loaded"
echo " Files:   ${INSTALL_DIR}"
echo " Service: mcs-matrix-tx.service (enabled)"
echo ""
echo " To edit config (IPs, ports):"
echo "   sudo nano /etc/systemd/system/mcs-matrix-tx.service"
echo "   sudo systemctl daemon-reload"
echo ""
echo " Starting service now..."
systemctl start mcs-matrix-tx
echo ""
echo " To watch logs:"
echo "   journalctl -u mcs-matrix-tx -f"
echo ""
