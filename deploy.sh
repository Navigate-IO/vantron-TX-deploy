#!/bin/bash
# deploy.sh for TX Pi (Vantron VT-USB-AH-8108)
#
# This is the ONLY script you need to run on a fresh Pi.
# It runs the install script (clones repos, loads driver, installs JDK,
# configures AP on onboard WiFi), then configures everything for TX.
#
# Prerequisites: Pi must already have the patched 6.6.x kernel with
# Morse Micro driver modules and firmware installed.
#
# Usage:
#   git clone https://github.com/Navigate-IO/vantron-tx-deploy.git
#   cd vantron-tx-deploy
#   sudo bash deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/mcs-test"

# Paths that install script will create
INSTALL_SCRIPT_REPO="/home/pi/vantron-install-script"
MCS_TEST_DIR="/home/pi/Recieve-Transfer-MCS-Test"
DRONE_DIR="/home/pi/drone-public"

# --- TX-specific config ---
WLAN1_IP="192.168.40.20"
OTHER_DRONE_URL="http://192.168.50.2/messenger"

echo "============================================"
echo " Vantron MCS Matrix TX — Full Setup"
echo "============================================"

# -----------------------------------------------------------
# 1. Clone and run the install script
# -----------------------------------------------------------
echo ""
echo "[1/6] Running install script..."

if [ -d "$INSTALL_SCRIPT_REPO" ]; then
    echo "  → install-script repo exists, pulling latest..."
    git -C "$INSTALL_SCRIPT_REPO" pull
else
    git clone https://github.com/Navigate-IO/vantron-install-script.git "$INSTALL_SCRIPT_REPO"
fi

bash "$INSTALL_SCRIPT_REPO/install-script.sh"

# -----------------------------------------------------------
# 2. Verify repos were cloned
# -----------------------------------------------------------
echo ""
echo "[2/6] Verifying dependencies..."

for dir in "$MCS_TEST_DIR" "$DRONE_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "ERROR: Expected $dir to exist after install script."
        exit 1
    fi
done
echo "  All repos present."

# -----------------------------------------------------------
# 3. Install MCS test files
# -----------------------------------------------------------
echo ""
echo "[3/6] Installing MCS test files to ${INSTALL_DIR}..."
sudo mkdir -p "$INSTALL_DIR"

sudo cp "$MCS_TEST_DIR/tx_matrix.py"              "$INSTALL_DIR/"
sudo cp "$MCS_TEST_DIR/rx_control.py"             "$INSTALL_DIR/"
sudo cp "$VANTRON_MESH_DIR/vantron-mesh.sh"       "$INSTALL_DIR/"

sudo chmod +x "$INSTALL_DIR"/*.py "$INSTALL_DIR"/*.sh 2>/dev/null || true

# -----------------------------------------------------------
# 4. Configure wlan1 static IP for AP
# -----------------------------------------------------------
echo ""
echo "[4/6] Configuring wlan1 with static IP ${WLAN1_IP}..."

sudo sed -i '/^# .* Pi - AP interface$/,/^nohook wpa_supplicant$/d' /etc/dhcpcd.conf 2>/dev/null || true
sudo sed -i '/^interface wlan1$/,/^nohook wpa_supplicant$/d' /etc/dhcpcd.conf 2>/dev/null || true

sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOF

# TX Pi - AP interface
interface wlan1
static ip_address=${WLAN1_IP}/16
nohook wpa_supplicant
EOF

sudo systemctl restart dhcpcd 2>/dev/null || true
sudo systemctl restart hostapd 2>/dev/null || true
sudo systemctl restart dnsmasq 2>/dev/null || true

# -----------------------------------------------------------
# 5. Configure drone-public
# -----------------------------------------------------------
echo ""
echo "[5/6] Configuring drone-public..."

DRONE_CONFIG="$DRONE_DIR/deployment/server_config.json"
if [ -f "$DRONE_CONFIG" ]; then
    sed -i "s|\"otherDronesUrls\":.*|\"otherDronesUrls\": \"${OTHER_DRONE_URL}\",|" "$DRONE_CONFIG"
    sed -i "s|\"actualIpAddress\":.*|\"actualIpAddress\": \"${WLAN1_IP}\",|" "$DRONE_CONFIG"
    echo "  → otherDronesUrls: ${OTHER_DRONE_URL}"
    echo "  → actualIpAddress: ${WLAN1_IP}"
else
    echo "  WARNING: $DRONE_CONFIG not found"
fi

# -----------------------------------------------------------
# 6. Install systemd services
# -----------------------------------------------------------
echo ""
echo "[6/6] Installing systemd services..."

sudo cp "$SCRIPT_DIR/mcs-matrix-tx.service" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/drone-server.service" /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable mcs-matrix-tx.service

echo ""
echo "============================================"
echo " TX setup complete!"
echo "============================================"
echo ""
echo " Driver:  loaded (morse + dot11ah)"
echo " Files:   ${INSTALL_DIR}"
echo " Service: mcs-matrix-tx.service (enabled)"
echo " Service: drone-server.service (starts after MCS sweep)"
echo " AP:      wlan1 → SSID: uas6, IP: ${WLAN1_IP}"
echo " Drone:   otherDronesUrls → ${OTHER_DRONE_URL}"
echo " JDK:     $(java -version 2>&1 | head -1)"
echo ""
echo " Starting services now..."
sudo systemctl start mcs-matrix-tx
echo ""
echo " To watch logs:"
echo "   journalctl -u mcs-matrix-tx -f"
echo "   journalctl -u drone-server -f"
echo ""
