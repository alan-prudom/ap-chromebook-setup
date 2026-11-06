#!/usr/bin/env bash
# ==============================================================================
# start-tailscale.sh
# Ensures tailscaled daemon is active and brings Tailscale up.
# Works via systemd if available, with direct daemon fallback.
# ==============================================================================

set -euo pipefail

# Ensure script is run as root or with sudo
if [[ $EUID -ne 0 ]]; then
    echo "[-] This script must be run as root (or with sudo)." >&2
    exit 1
fi

echo "[*] Checking Tailscale daemon status..."

# 1. If running under systemd
if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
    if ! systemctl is-active --quiet tailscaled; then
        echo "[+] Starting tailscaled via systemctl..."
        systemctl start tailscaled
    else
        echo "[✓] tailscaled systemd service is already running."
    fi
else
    # 2. Fallback for containers / non-systemd environments
    if ! pgrep -x tailscaled >/dev/null 2>&1; then
        echo "[+] Starting tailscaled directly in background..."
        mkdir -p /var/run/tailscale /var/lib/tailscale /var/log
        nohup /usr/sbin/tailscaled \
            --state=/var/lib/tailscale/tailscaled.state \
            --socket=/var/run/tailscale/tailscaled.sock \
            --port=41641 \
            > /var/log/tailscaled.log 2>&1 &
        sleep 2
    else
        echo "[✓] tailscaled process is already running."
    fi
fi

# 3. Bring Tailscale link up if not connected
echo "[*] Verifying Tailscale connection state..."
if command -v tailscale >/dev/null 2>&1; then
    STATUS=$(tailscale status 2>&1 || true)
    if echo "$STATUS" | grep -qi "Tailscale is stopped"; then
        echo "[+] Running 'tailscale up'..."
        tailscale up --ssh --accept-routes
    elif echo "$STATUS" | grep -qi "NeedsLogin"; then
        echo "[!] Tailscale needs login. Run: tailscale up"
    else
        echo "[✓] Tailscale is connected:"
        tailscale status --peers=false || true
    fi
else
    echo "[-] 'tailscale' CLI not found in PATH." >&2
fi
