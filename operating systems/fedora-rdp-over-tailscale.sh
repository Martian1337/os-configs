#!/usr/bin/env bash
#
# fedora-rdp-tailscale.sh
# Configure GNOME Remote Desktop (system "Remote Login" RDP) reachable ONLY
# over a Tailscale tailnet, on Fedora Workstation (GNOME / Wayland).
#
# What it does:
#   1. Installs tailscale, gnome-remote-desktop, openssl (from Fedora's own repos,
#      which sidesteps the DNF5 --add-repo breakage / F43+ repo 404s)
#   2. Brings the host onto your tailnet (optionally with Tailscale SSH)
#   3. Generates a self-signed TLS cert for the system RDP service
#   4. Sets the system RDP credential and enables the service
#   5. Scopes firewalld so 3389 is reachable ONLY over tailscale0 (never LAN/WAN)
#
# Re-runnable: safe to run again; existing config is reused unless FORCE_CERT=1.
#
# Usage:
#   sudo ./fedora-rdp-tailscale.sh
#   sudo RDP_USER=server FIREWALL_MODE=port ./fedora-rdp-tailscale.sh
#
# Notes:
#   - Keep SELinux enforcing; current gnome-remote-desktop ships proper policy.
#   - The "TPM credentials failed / No TPM device found" line is a benign fallback
#     (credentials stored in a keyfile instead of hardware-sealed). RDP still works.
#
set -euo pipefail

# ---- Configuration (override via environment) -------------------------------
RDP_USER="${RDP_USER:-}"                     # system RDP username (prompted if empty)
RDP_PASS="${RDP_PASS:-}"                     # system RDP password (prompted if empty — prompting is safer)
CERT_DAYS="${CERT_DAYS:-3650}"               # TLS cert validity in days
FIREWALL_MODE="${FIREWALL_MODE:-trusted}"    # "trusted" = all tailnet traffic to host
                                             # "port"    = only SSH + 3389 over the tailnet
FORCE_CERT="${FORCE_CERT:-0}"                # 1 = regenerate TLS cert even if one exists
ENABLE_TS_SSH="${ENABLE_TS_SSH:-1}"          # 1 = also enable Tailscale SSH (tailnet-brokered, no host keys)
TS_IFACE="tailscale0"
GRD_USER="gnome-remote-desktop"
GRD_HOME="/var/lib/gnome-remote-desktop"
CERT="${GRD_HOME}/rdp-tls.crt"
KEY="${GRD_HOME}/rdp-tls.key"

# ---- Pretty logging ---------------------------------------------------------
c_g=$'\e[32m'; c_y=$'\e[33m'; c_r=$'\e[31m'; c_b=$'\e[1m'; c_0=$'\e[0m'
info(){ printf '%s[*]%s %s\n' "$c_g" "$c_0" "$*"; }
warn(){ printf '%s[!]%s %s\n' "$c_y" "$c_0" "$*"; }
err(){  printf '%s[x]%s %s\n' "$c_r" "$c_0" "$*" >&2; }
step(){ printf '\n%s==> %s%s\n' "$c_b" "$*" "$c_0"; }
die(){ err "$*"; exit 1; }

# ---- Preflight --------------------------------------------------------------
step "Preflight checks"
[ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)."
command -v dnf >/dev/null || die "dnf not found — this script targets Fedora."
[ -r /etc/os-release ] && . /etc/os-release
[ "${ID:-}" = "fedora" ] || warn "Non-Fedora system (ID=${ID:-unknown}); continuing anyway."
info "Host: $(hostname)  |  ${PRETTY_NAME:-unknown}"

# ---- Install packages -------------------------------------------------------
step "Installing packages"
dnf install -y tailscale gnome-remote-desktop openssl
# Ensure the grd system user exists (guards a known missing-user startup crash)
systemd-sysusers >/dev/null 2>&1 || true

# ---- Tailscale --------------------------------------------------------------
step "Bringing up Tailscale"
systemctl enable --now tailscaled
ts_ssh_flag=""; [ "$ENABLE_TS_SSH" = "1" ] && ts_ssh_flag="--ssh"
if tailscale status >/dev/null 2>&1; then
  info "Tailscale already authenticated."
  # Node is already up — toggle the SSH setting without re-running the full 'up' flow.
  if [ "$ENABLE_TS_SSH" = "1" ]; then
    if tailscale set --ssh=true 2>/dev/null; then
      info "Tailscale SSH enabled."
    else
      warn "Couldn't toggle Tailscale SSH via 'set'; run 'sudo tailscale up --ssh' manually."
    fi
  fi
else
  warn "Opening Tailscale login — visit the URL it prints to authenticate."
  tailscale up $ts_ssh_flag
fi
# Wait for the interface to come up before touching the firewall
for _ in $(seq 1 15); do
  ip link show "$TS_IFACE" >/dev/null 2>&1 && break
  sleep 1
done
ip link show "$TS_IFACE" >/dev/null 2>&1 || die "$TS_IFACE never appeared; is Tailscale up?"
TS_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
info "Tailscale IPv4: ${TS_IP:-unknown}"

# ---- Credentials ------------------------------------------------------------
step "System RDP credential"
if [ -z "$RDP_USER" ]; then
  read -rp "  RDP username [server]: " RDP_USER
  RDP_USER="${RDP_USER:-server}"
fi
if [ -z "$RDP_PASS" ]; then
  read -rsp "  RDP password: " RDP_PASS; echo
  read -rsp "  Confirm password: " RDP_PASS2; echo
  [ "$RDP_PASS" = "$RDP_PASS2" ] || die "Passwords did not match."
fi
[ -n "$RDP_PASS" ] || die "Password must not be empty."

# ---- TLS certificate --------------------------------------------------------
step "TLS certificate"
install -d -o "$GRD_USER" -g "$GRD_USER" -m 0700 "$GRD_HOME"
if [ "$FORCE_CERT" = "1" ] || [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
  info "Generating self-signed RDP certificate (valid ${CERT_DAYS} days)."
  openssl req -x509 -newkey rsa:4096 -nodes -days "$CERT_DAYS" \
    -subj "/CN=$(hostname)" -keyout "$KEY" -out "$CERT"
  chown "$GRD_USER":"$GRD_USER" "$CERT" "$KEY"
  chmod 600 "$KEY"; chmod 644 "$CERT"
else
  info "Existing certificate found — reusing (set FORCE_CERT=1 to regenerate)."
fi

# ---- Configure GNOME Remote Desktop (system mode) ---------------------------
step "Configuring GNOME Remote Desktop"
grdctl --system rdp set-tls-cert "$CERT"
grdctl --system rdp set-tls-key  "$KEY"
# NOTE: passing the password as an arg is briefly visible in `ps`; acceptable for a
# local root-run script. grdctl also accepts it via stdin if you prefer.
grdctl --system rdp set-credentials "$RDP_USER" "$RDP_PASS"
grdctl --system rdp enable
systemctl enable --now gnome-remote-desktop.service
info "Current status:"; grdctl --system status || true

# ---- Firewall ---------------------------------------------------------------
step "Firewall (scoping RDP to the tailnet)"
if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
  case "$FIREWALL_MODE" in
    trusted)
      firewall-cmd --permanent --zone=trusted --add-interface="$TS_IFACE" >/dev/null 2>&1 || true
      info "$TS_IFACE -> 'trusted' zone (all tailnet traffic allowed to host)."
      ;;
    port)
      # Tighter: a dedicated zone that allows only SSH + RDP over the tailnet.
      firewall-cmd --permanent --new-zone=tailnet-rdp >/dev/null 2>&1 || true
      firewall-cmd --permanent --zone=trusted --remove-interface="$TS_IFACE" >/dev/null 2>&1 || true
      firewall-cmd --permanent --zone=tailnet-rdp --add-interface="$TS_IFACE" >/dev/null 2>&1 || true
      firewall-cmd --permanent --zone=tailnet-rdp --add-service=ssh >/dev/null 2>&1 || true
      firewall-cmd --permanent --zone=tailnet-rdp --add-port=3389/tcp >/dev/null 2>&1 || true
      info "$TS_IFACE -> 'tailnet-rdp' zone (only SSH + 3389 over tailnet)."
      ;;
    *)
      die "Unknown FIREWALL_MODE '$FIREWALL_MODE' (use 'trusted' or 'port')."
      ;;
  esac
  firewall-cmd --reload >/dev/null
  info "Zone of $TS_IFACE: $(firewall-cmd --get-zone-of-interface="$TS_IFACE" 2>/dev/null || echo unknown)"
else
  warn "firewalld not active — skipping. Ensure 3389/tcp is reachable only over $TS_IFACE by other means."
fi

# ---- Summary ----------------------------------------------------------------
step "Done"
if ss -tlnp 2>/dev/null | grep -q ':3389'; then
  info "RDP is listening on :3389."
else
  warn "Nothing listening on :3389 yet — check 'grdctl --system status'."
fi
cat <<EOF

  Connect from any device on your tailnet:
    Host : ${TS_IP:-<tailscale-ip>}   (or MagicDNS name: $(hostname))
    Port : 3389
    Auth : ${RDP_USER} / <your RDP password>  ->  then log in at GDM as your Fedora user

  Clients: mstsc (Windows) - Windows App (macOS) - Remmina / FreeRDP (Linux)
$( [ "$ENABLE_TS_SSH" = "1" ] && printf '
  Tailscale SSH: ssh <your-user>@%s
    Brokered by your tailnet identity (no host keys). Requires a matching
    "ssh" rule in your tailnet ACL policy, or connections will be denied.
' "${TS_IP:-<tailscale-ip>}" )
  Tip: for per-device access control, gate port 3389 with a Tailscale ACL
  instead of widening the firewall.
EOF
