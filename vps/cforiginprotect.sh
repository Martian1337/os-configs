#!/usr/bin/env bash

set -euo pipefail

CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

TMP_DIR="$(mktemp -d)"
TMP_V4="$TMP_DIR/cf-ips-v4.txt"
TMP_V6="$TMP_DIR/cf-ips-v6.txt"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Ask for firewall type
echo "Select firewall type:"
echo "  1) ufw"
echo "  2) iptables/ip6tables"
read -rp "Enter choice [1-2]: " FW_CHOICE

case "$FW_CHOICE" in
  1)
    FIREWALL="ufw"
    ;;
  2)
    FIREWALL="iptables"
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac

# Ask for IP version
echo "Select IP version:"
echo "  1) IPv4 only"
echo "  2) IPv6 only"
echo "  3) Both IPv4 and IPv6"
read -rp "Enter choice [1-3]: " IP_CHOICE

USE_V4=false
USE_V6=false
case "$IP_CHOICE" in
  1)
    USE_V4=true
    ;;
  2)
    USE_V6=true
    ;;
  3)
    USE_V4=true
    USE_V6=true
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac

echo "Downloading Cloudflare IP ranges..."
$USE_V4 && curl -fsSL "$CF_IPV4_URL" -o "$TMP_V4"
$USE_V6 && curl -fsSL "$CF_IPV6_URL" -o "$TMP_V6"

if [[ "$FIREWALL" == "ufw" ]]; then
  echo "Using ufw rules for ports 80 and 443..."

  if $USE_V4; then
    while read -r cfip; do
      [[ -z "$cfip" ]] && continue
      echo "ufw allow proto tcp from $cfip to any port 80,443 comment 'Cloudflare IPv4'" 
      ufw allow proto tcp from "$cfip" to any port 80,443 comment 'Cloudflare IPv4'
    done < "$TMP_V4"
  fi

  if $USE_V6; then
    while read -r cfip; do
      [[ -z "$cfip" ]] && continue
      echo "ufw allow proto tcp from $cfip to any port 80,443 comment 'Cloudflare IPv6'"
      ufw allow proto tcp from "$cfip" to any port 80,443 comment 'Cloudflare IPv6'
    done < "$TMP_V6"
  fi

  echo "Reloading ufw..."
  ufw reload

else
  echo "Using iptables/ip6tables rules for ports 80 and 443..."

  if $USE_V4; then
    while read -r cfip; do
      [[ -z "$cfip" ]] && continue
      echo "iptables -I INPUT -p tcp -m multiport --dports 80,443 -s $cfip -j ACCEPT"
      iptables -I INPUT -p tcp -m multiport --dports 80,443 -s "$cfip" -j ACCEPT
    done < "$TMP_V4"
  fi

  if $USE_V6; then
    while read -r cfip; do
      [[ -z "$cfip" ]] && continue
      echo "ip6tables -I INPUT -p tcp -m multiport --dports 80,443 -s $cfip -j ACCEPT"
      ip6tables -I INPUT -p tcp -m multiport --dports 80,443 -s "$cfip" -j ACCEPT
    done < "$TMP_V6"
  fi

  echo "Remember to save your iptables/ip6tables rules (e.g. with iptables-persistent) so they persist after reboot."
fi

echo "Done."
