#!/bin/bash
#
# Overwatch Agent Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/gabegon8910/overwatch/main/agent/install.sh | bash -s -- --url https://overwatch.example.com --token YOUR_TOKEN
#
set -e

INSTALL_DIR="/opt/overwatch-agent"
SERVICE_NAME="overwatch-agent"
AGENT_SCRIPT_URL="https://raw.githubusercontent.com/gabegon8910/overwatch/main/agent/overwatch-agent.py"

echo "=== Overwatch Agent Installer ==="
echo ""

while [ $# -gt 0 ]; do
    case "$1" in
        --url)   SERVER_URL="$2"; shift 2 ;;
        --token) AGENT_TOKEN="$2"; shift 2 ;;
        *)       echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$SERVER_URL" ]; then
    read -p "Overwatch Server URL (e.g. https://overwatch.example.com): " SERVER_URL
fi
if [ -z "$AGENT_TOKEN" ]; then
    read -p "Agent Token: " AGENT_TOKEN
fi

if [ -z "$SERVER_URL" ] || [ -z "$AGENT_TOKEN" ]; then
    echo "Error: Server URL and Agent Token are required."
    exit 1
fi

# Strip trailing slash
SERVER_URL="${SERVER_URL%/}"

# Install dependencies
echo "Installing Python dependencies..."
if command -v pip3 &>/dev/null; then
    pip3 install --quiet psutil requests
elif command -v pip &>/dev/null; then
    pip install --quiet psutil requests
else
    echo "Error: pip not found. Install Python 3 and pip first."
    echo "  apt install python3-pip    # Debian/Ubuntu"
    echo "  yum install python3-pip    # RHEL/CentOS"
    exit 1
fi

# Download agent script
echo "Downloading agent..."
mkdir -p "$INSTALL_DIR"

if command -v curl &>/dev/null; then
    curl -fsSL "$AGENT_SCRIPT_URL" -o "$INSTALL_DIR/overwatch-agent.py"
elif command -v wget &>/dev/null; then
    wget -q "$AGENT_SCRIPT_URL" -O "$INSTALL_DIR/overwatch-agent.py"
else
    echo "Error: curl or wget required."
    exit 1
fi
chmod +x "$INSTALL_DIR/overwatch-agent.py"

# Create systemd service
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Overwatch Monitoring Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/overwatch-agent.py --url "${SERVER_URL}" --token "${AGENT_TOKEN}"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

echo ""
echo "=== Agent installed and started ==="
echo "Check status: systemctl status ${SERVICE_NAME}"
echo "View logs:    journalctl -u ${SERVICE_NAME} -f"
