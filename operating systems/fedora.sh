#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status, treat unset variables as errors, and catch pipeline failures
set -euo pipefail

# 0. Pre-flight Root and User Check
if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run this script with sudo or as root."
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
if [ "$TARGET_USER" = "root" ]; then
    echo "[-] Warning: Running directly as root. Please specify your standard desktop username:"
    read -rp "Username: " TARGET_USER
fi

USER_HOME=$(eval echo "~$TARGET_USER")

echo "[+] Starting Comprehensive Fedora Workstation Setup & Libvirt Hardening..."

# 1. Package Managers & Repositories Setup
echo "[+] Installing Snap and Flatpak..."
dnf install -y snapd flatpak
systemctl enable --now snapd.socket
if [ ! -e /usr/bin/snap ]; then
    ln -s /usr/lib/snapd/snap /usr/bin/snap
fi
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Mullvad VPN
echo "[+] Adding Mullvad repository..."
dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo || true
dnf install -y mullvad-vpn libappindicator-gtk3

# ProtonVPN
echo "[+] Installing ProtonVPN stack..."
FEDORA_VERSION=$(rpm -E %fedora)
PROTON_RPM="protonvpn-stable-release-1.0.3-1.noarch.rpm"
wget -q "https://repo.protonvpn.com/fedora-${FEDORA_VERSION}-stable/protonvpn-stable-release/${PROTON_RPM}"
dnf install -y "./${PROTON_RPM}"
rm -f "${PROTON_RPM}"

# Force immediate metadata sync so DNF recognizes the new packages
dnf clean expire-cache
dnf makecache

dnf install -y proton-vpn-gnome-desktop libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app openresolv

mkdir -p /etc/openvpn
wget -q "https://raw.githubusercontent.com/ProtonVPN/scripts/master/update-resolv-conf.sh" -O "/etc/openvpn/update-resolv-conf"
chmod +x "/etc/openvpn/update-resolv-conf"

# Mullvad Browser
dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo || true
dnf install -y mullvad-browser

# LibreWolf
echo "[+] Adding LibreWolf repository..."
curl -fsSL https://repo.librewolf.net/librewolf.repo | tee /etc/yum.repos.d/librewolf.repo
dnf install -y librewolf

# VSCodium
echo "[+] Installing VSCodium..."
rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=download.vscodium.com\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg\nmetadata_expire=1h\n" | tee /etc/yum.repos.d/vscodium.repo
dnf install -y codium

# Lokinet
echo "[+] Installing Lokinet..."
dnf config-manager addrepo --from-repofile=https://rpm.oxen.io/fedora/oxen.repo || true
dnf install -y lokinet
systemctl enable lokinet --now

# 2. Virtualization Stack & Advanced Hardening (Libvirt/KVM)
echo "[+] Installing and Hardening Virtualization Stack..."
dnf install -y @virtualization qemu-kvm libvirt virt-install virt-manager bridge-utils

systemctl enable --now libvirtd

# Assign user to virtualization groups
usermod -aG libvirt,kvm "$TARGET_USER"

# Harden /etc/libvirt/libvirtd.conf safely
LIBVIRTD_CONF="/etc/libvirt/libvirtd.conf"
[ ! -f "${LIBVIRTD_CONF}.bak" ] && cp "$LIBVIRTD_CONF" "${LIBVIRTD_CONF}.bak"

cat << 'EOF' >> "$LIBVIRTD_CONF"

# Hardened overrides
listen_tls = 0
listen_tcp = 0
auth_tcp = "sasl"
unix_sock_group = "libvirt"
unix_sock_ro_perms = "0777"
unix_sock_rw_perms = "0770"
auth_unix_ro = "none"
auth_unix_rw = "polkit"
EOF

# Harden /etc/libvirt/qemu.conf safely
QEMU_CONF="/etc/libvirt/qemu.conf"
[ ! -f "${QEMU_CONF}.bak" ] && cp "$QEMU_CONF" "${QEMU_CONF}.bak"

cat << 'EOF' >> "$QEMU_CONF"

# Hardened overrides
user = "qemu"
group = "qemu"
dynamic_ownership = 1
EOF

# Ensure SELinux enforcement for sVirt VM isolation
if [ "$(getenforce)" != "Enforcing" ]; then
    setenforce 1
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
fi

systemctl restart libvirtd

# 3. Security, Privacy, and Auditing Tools
echo "[+] Purging crash reporting tools (ABRT) for privacy..."
systemctl disable --now abrtd.service abrt-ccpp.service 2>/dev/null || true
dnf remove -y abrt drkonqi 2>/dev/null || true

echo "[+] Installing security auditing & protection software..."
dnf install -y lynis fail2ban bleachbit mat2 clamav clamd clamav-update clamtk

systemctl stop clamav-freshclam 2>/dev/null || true
freshclam || true
systemctl enable --now fail2ban clamav-freshclam.service

# Setup automated cron scans for Lynis and ClamAV
echo "[+] Scheduling automated security audits..."
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/lynis audit system --cronjob >> /var/log/lynis.log 2>&1") | crontab -
mkdir -p /var/log/clamav
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/freshclam --quiet && /usr/bin/clamscan -r / --quiet --log=/var/log/clamav/scan.log") | crontab -

# 4. Flatpak and AppImage Applications
echo "[+] Installing Flatpak apps..."
flatpak install -y flathub eu.betterbird.Betterbird
flatpak install -y flathub com.bitwarden.desktop
flatpak install -y flathub com.github.wwmm.easyeffects

# Tuta Desktop AppImage integration
echo "[+] Installing Tuta Desktop..."
sudo -u "$TARGET_USER" mkdir -p "$USER_HOME/Applications" "$USER_HOME/Desktop"
sudo -u "$TARGET_USER" curl -L https://app.tuta.com/desktop/tuta-desktop-linux.AppImage -o "$USER_HOME/Applications/tuta.AppImage"
sudo -u "$TARGET_USER" chmod +x "$USER_HOME/Applications/tuta.AppImage"

cat << EOF > "$USER_HOME/Desktop/Tuta.desktop"
[Desktop Entry]
Name=Tuta
Exec=$USER_HOME/Applications/tuta.AppImage
Icon=mail-message-new
Type=Application
Categories=Network;Email;
Terminal=false
EOF
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/Desktop/Tuta.desktop"
chmod +x "$USER_HOME/Desktop/Tuta.desktop"

echo "=================================================================="
echo "[+] Complete system deployment and virtualization hardening finished!"
echo "[+] IMPORTANT: Please log out and back in (or reboot your system)"
echo "    to fully apply the libvirt/kvm user group permissions."
echo "=================================================================="
