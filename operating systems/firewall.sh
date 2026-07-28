#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

echo "=== Starting UFW Hardening for Tailscale ==="

# 1. Reset UFW to a clean, default state
echo "Resetting UFW rules..."
ufw --force reset

# 2. Set strict default policies
echo "Setting default policies (Block incoming, Allow outgoing)..."
ufw default deny incoming
ufw default allow outgoing

# 3. Apply Tailscale-exclusive rules
echo "Allowing RDP (3389) ONLY via Tailscale..."
ufw allow in on tailscale0 to any port 3389 proto tcp

echo "Allowing SSH (22) ONLY via Tailscale (with rate limiting)..."
ufw limit in on tailscale0 to any port 22 proto tcp

# 4. Enable UFW
echo "Enabling UFW..."
ufw --force enable

# 5. Show final status
echo "=== Final UFW Configuration ==="
ufw status verbose
