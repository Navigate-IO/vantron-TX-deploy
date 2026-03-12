#!/bin/bash
# deploy.sh for TX Pi
#
# This is the ONLY script you need to run on a fresh Pi.
# It runs the install script (clones repos, builds driver, loads modules,
# installs JDK, RaspAP, drone-public), then configures everything for TX.
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
DRONE_DIR="/home/pi/drone-public"

# --- TX-specific config ---
WLAN1_IP="192.168.40.20"
OTHER_DRONE_URL="http://192.168.50.2/messenger"

echo "============================================"
echo " MCS Matrix TX — Full Setup"
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
    git clone https://github.com/Navigate-IO/install-script.git "$INSTALL_SCRIPT_REPO"
fi

bash "$INSTALL_SCRIPT_REPO/install-script.sh"

# -----------------------------------------------------------
# 2. Verify repos were cloned
# -----------------------------------------------------------
echo ""
echo "[2/6] Verifying dependencies..."

for dir in "$MCS_TEST_DIR" "$BATMAN_DIR" "$DRONE_DIR"; do
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
mkdir -p "$INSTALL_DIR"

cp "$MCS_TEST_DIR/tx_matrix.py"     "$INSTALL_DIR/"
cp "$MCS_TEST_DIR/rx_control.py"    "$INSTALL_DIR/"
cp "$BATMAN_DIR/sdmah-mesh.sh"      "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR"/*.py "$INSTALL_DIR"/*.sh 2>/dev/null || true

# -----------------------------------------------------------
# 4. Configure wlan1 static IP for AP
# -----------------------------------------------------------
echo ""
echo "[4/6] Configuring wlan1 with static IP ${WLAN1_IP}..."

# Remove any existing wlan1 block, then add fresh
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
cp "$SCRIPT_DIR/mcs-matrix-tx.service" /etc/systemd/system/
cp "$SCRIPT_DIR/drone-server.service" /etc/systemd/system/

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
echo " Service: drone-server.service (enabled)"
echo " AP:      wlan1 → SSID: uas6, IP: ${WLAN1_IP}"
echo " Drone:   otherDronesUrls → ${OTHER_DRONE_URL}"
echo " JDK:     $(java -version 2>&1 | head -1)"
echo ""
echo " To edit config (IPs, ports):"
echo "   sudo nano /etc/systemd/system/mcs-matrix-tx.service"
echo "   sudo systemctl daemon-reload"
echo ""
echo " Starting services now..."
systemctl start mcs-matrix-tx
systemctl start drone-server
echo ""
echo " To watch logs:"
echo "   journalctl -u mcs-matrix-tx -f"
echo "   journalctl -u drone-server -f"
echo ""
