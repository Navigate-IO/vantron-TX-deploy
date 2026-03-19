#!/bin/bash
# deploy.sh for TX Pi (Vantron VT-USB-AH-8108)
#
# Run on a Pi that already has:
#   - Kernel 6.6.x with Morse Micro patches compiled and installed
#   - Morse Micro driver modules (morse.ko, dot11ah.ko) in /lib/modules/
#   - Firmware files in /lib/firmware/morse/
#   - morsectrl and morse_cli in /usr/bin/
#
# This script sets up the software stack: repos, mesh, AP, MCS tests, drone server.
#
# Usage:
#   git clone https://github.com/Navigate-IO/vantron-tx-deploy.git
#   cd vantron-tx-deploy
#   sudo bash deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/mcs-test"

VANTRON_MESH_DIR="/home/pi/vantron-mesh"
MCS_TEST_DIR="/home/pi/Recieve-Transfer-MCS-Test"
DRONE_DIR="/home/pi/drone-public"

# --- TX-specific config ---
WLAN1_IP="192.168.40.20"
OTHER_DRONE_URL="http://192.168.50.2/messenger"

echo "============================================"
echo " Vantron MCS Matrix TX — Full Setup"
echo "============================================"

# -----------------------------------------------------------
# 1. Install system dependencies
# -----------------------------------------------------------
echo ""
echo "[1/7] Installing system dependencies..."
sudo apt update
sudo apt install -y iperf3 batctl hostapd dnsmasq ca-certificates default-jdk

# -----------------------------------------------------------
# 2. Verify driver is loaded
# -----------------------------------------------------------
echo ""
echo "[2/7] Verifying Morse Micro driver..."

if ! lsmod | grep -q "^morse "; then
    echo "  Loading driver modules..."
    sudo modprobe dot11ah
    sudo modprobe morse
    sleep 5
fi

if ! iw dev | grep -q "wlan0"; then
    echo "ERROR: wlan0 (Vantron) not found. Is the dongle plugged in and driver installed?"
    exit 1
fi
echo "  → Driver loaded, wlan0 present"

# -----------------------------------------------------------
# 3. Clone repositories
# -----------------------------------------------------------
echo ""
echo "[3/7] Cloning repositories..."

for repo_url repo_dir in \
    "https://github.com/Navigate-IO/vantron-mesh.git" "$VANTRON_MESH_DIR" \
    "https://github.com/Navigate-IO/Recieve-Transfer-MCS-Test.git" "$MCS_TEST_DIR" \
    "https://github.com/Navigate-IO/drone-public.git" "$DRONE_DIR"; do
    if [ -d "$repo_dir" ]; then
        echo "  → $(basename $repo_dir) exists, pulling..."
        git -C "$repo_dir" pull || true
    else
        git clone "$repo_url" "$repo_dir"
    fi
done

# -----------------------------------------------------------
# 4. Install MCS test files
# -----------------------------------------------------------
echo ""
echo "[4/7] Installing MCS test files to ${INSTALL_DIR}..."
sudo mkdir -p "$INSTALL_DIR"

sudo cp "$MCS_TEST_DIR/tx_matrix.py"     "$INSTALL_DIR/"
sudo cp "$MCS_TEST_DIR/rx_control.py"    "$INSTALL_DIR/"
sudo cp "$SCRIPT_DIR/vantron-mesh.sh"    "$INSTALL_DIR/"

sudo chmod +x "$INSTALL_DIR"/*.py "$INSTALL_DIR"/*.sh 2>/dev/null || true

# -----------------------------------------------------------
# 5. Set up udev rules (wlan0=Vantron Morse, wlan1=onboard brcm)
# -----------------------------------------------------------
echo ""
echo "[5/7] Setting up udev rules..."
sudo tee /etc/udev/rules.d/70-wifi-names.rules > /dev/null <<'UDEVEOF'
# Vantron Morse Micro USB dongle → wlan0
SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="325b", NAME="wlan0"
# Onboard Broadcom WiFi → wlan1
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="brcmfmac", NAME="wlan1"
UDEVEOF
sudo udevadm control --reload-rules

# -----------------------------------------------------------
# 6. Configure AP on wlan1 (onboard WiFi)
# -----------------------------------------------------------
echo ""
echo "[6/7] Configuring AP on wlan1 (onboard WiFi)..."

sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true

sudo mkdir -p /etc/hostapd
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=wlan1
driver=nl80211
ssid=uas6
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=hello123
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sudo sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd 2>/dev/null || true

sudo mkdir -p /etc/dnsmasq.d
sudo tee /etc/dnsmasq.d/wlan1-ap.conf > /dev/null <<EOF
interface=wlan1
dhcp-range=192.168.40.100,192.168.40.200,255.255.0.0,24h
EOF

sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq

# Static IP for wlan1
sudo sed -i '/^# .* Pi - AP interface$/,/^nohook wpa_supplicant$/d' /etc/dhcpcd.conf 2>/dev/null || true
sudo sed -i '/^interface wlan1$/,/^nohook wpa_supplicant$/d' /etc/dhcpcd.conf 2>/dev/null || true
sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOF

# TX Pi - AP interface
interface wlan1
static ip_address=${WLAN1_IP}/16
nohook wpa_supplicant
EOF

sudo systemctl restart dhcpcd 2>/dev/null || true

# -----------------------------------------------------------
# 7. Configure drone-public and install services
# -----------------------------------------------------------
echo ""
echo "[7/7] Configuring drone-public and installing services..."

DRONE_CONFIG="$DRONE_DIR/deployment/server_config.json"
if [ -f "$DRONE_CONFIG" ]; then
    sed -i "s|\"otherDronesUrls\":.*|\"otherDronesUrls\": \"${OTHER_DRONE_URL}\",|" "$DRONE_CONFIG"
    sed -i "s|\"actualIpAddress\":.*|\"actualIpAddress\": \"${WLAN1_IP}\",|" "$DRONE_CONFIG"
fi

# Ensure driver loads on boot
sudo tee /etc/modules-load.d/morse.conf > /dev/null <<EOF
dot11ah
morse
EOF

# Install systemd services
sudo cp "$SCRIPT_DIR/mcs-matrix-tx.service" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/drone-server.service" /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable mcs-matrix-tx.service

echo ""
echo "============================================"
echo " Vantron TX setup complete!"
echo "============================================"
echo ""
echo " Mesh:    wlan0 (Vantron) → BATMAN-adv → bat0"
echo " AP:      wlan1 (onboard) → SSID: uas6, IP: ${WLAN1_IP}"
echo " Service: mcs-matrix-tx.service (enabled)"
echo " Service: drone-server.service (starts after MCS sweep)"
echo " Drone:   otherDronesUrls → ${OTHER_DRONE_URL}"
echo " JDK:     $(java -version 2>&1 | head -1)"
echo ""
echo " A reboot is recommended for udev rules to take effect."
echo ""
