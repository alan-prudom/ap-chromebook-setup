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

# 3. Ensure SSH service is running for remote access
echo "[*] Checking SSH daemon status..."
if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
    if ! systemctl is-active --quiet ssh; then
        echo "[+] Starting ssh service via systemctl..."
        systemctl enable --now ssh
    else
        echo "[✓] SSH service is already running."
    fi
elif command -v service >/dev/null 2>&1; then
    if ! service ssh status >/dev/null 2>&1; then
        echo "[+] Starting ssh service via service..."
        service ssh start
    else
        echo "[✓] SSH service is already running."
    fi
fi

# 4. Bring Tailscale link up if not connected
echo "[*] Verifying Tailscale connection state..."
if command -v tailscale >/dev/null 2>&1; then
    # Allow a brief moment if tailscaled was just started
    for _ in {1..10}; do
        STATUS=$(tailscale status 2>&1 || true)
        if echo "$STATUS" | grep -qi "Tailscale is starting"; then
            sleep 1
        else
            break
        fi
    done

    if echo "$STATUS" | grep -qi "Tailscale is stopped"; then
        echo "[+] Running 'tailscale up'..."
        tailscale up --ssh --accept-routes
    elif echo "$STATUS" | grep -qi "NeedsLogin"; then
        echo "[!] Tailscale needs login. Run: tailscale up"
    else
        echo "[✓] Tailscale is connected:"
        tailscale status --peers=false || true
    fi

    # Display active Tailscale IP for easy reference
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
    if [[ -n "$TS_IP" ]]; then
        echo "[i] Tailscale IPv4: $TS_IP"
        echo "[i] Connect via: ssh alanp2@$TS_IP"
    fi
else
    echo "[-] 'tailscale' CLI not found in PATH." >&2
fi
