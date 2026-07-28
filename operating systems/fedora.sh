#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

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
dnf config-manager --add-repo=https://repository.mullvad.net/rpm/stable/mullvad.repo || dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo
dnf install -y mullvad-vpn

# ProtonVPN
echo "[+] Installing ProtonVPN stack..."
fedora_version=$(rpm -E %fedora)
wget -q "https://repo.protonvpn.com/fedora-${fedora_version}-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.3-1.noarch.rpm"
dnf install -y ./protonvpn-stable-release-1.0.3-1.noarch.rpm proton-vpn-gnome-desktop libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app openresolv
rm -f protonvpn-stable-release-1.0.3-1.noarch.rpm
dnf check-update --refresh || true
wget -q "https://raw.githubusercontent.com/ProtonVPN/scripts/master/update-resolv-conf.sh" -O "/etc/openvpn/update-resolv-conf"
chmod +x "/etc/openvpn/update-resolv-conf"

# Brave Browser
echo "[+] Adding Brave repository and installing..."
dnf install -y dnf-plugins-core
dnf config-manager --add-repo=https://brave-browser-rpm-release.s3.brave.com/x86_64/ || true
dnf install -y brave-browser

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
dnf config-manager --add-repo https://rpm.oxen.io/fedora/oxen.repo || true
dnf install -y lokinet
systemctl enable lokinet --now

# 2. Virtualization Stack & Advanced Hardening (Libvirt/KVM)
echo "[+] Installing and Hardening Virtualization Stack..."
dnf install -y @virtualization qemu-kvm libvirt virt-install virt-manager bridge-utils

systemctl enable --now libvirtd

# Assign user to virtualization groups
usermod -aG libvirt,kvm "$TARGET_USER"

# Harden /etc/libvirt/libvirtd.conf
LIBVIRTD_CONF="/etc/libvirt/libvirtd.conf"
[ ! -f "${LIBVIRTD_CONF}.bak" ] && cp "$LIBVIRTD_CONF" "${LIBVIRTD_CONF}.bak"

sed -i 's/^#\(listen_tls = \).*/\10/' "$LIBVIRTD_CONF"
sed -i 's/^#\(listen_tcp = \).*/\10/' "$LIBVIRTD_CONF"
sed -i 's/^#\(auth_tcp = \).*/\1- "sasl"/g' "$LIBVIRTD_CONF"
sed -i 's/^#\(unix_sock_group = \).*/\1"libvirt"/' "$LIBVIRTD_CONF"
sed -i 's/^#\(unix_sock_ro_perms = \).*/\1"0777"/' "$LIBVIRTD_CONF"
sed -i 's/^#\(unix_sock_rw_perms = \).*/\1"0770"/' "$LIBVIRTD_CONF"
sed -i 's/^#\(auth_unix_ro = \).*/\1"none"/' "$LIBVIRTD_CONF"
sed -i 's/^#\(auth_unix_rw = \).*/\1"polkit"/' "$LIBVIRTD_CONF"

# Harden /etc/libvirt/qemu.conf (Run QEMU safely as non-root qemu:qemu)
QEMU_CONF="/etc/libvirt/qemu.conf"
[ ! -f "${QEMU_CONF}.bak" ] && cp "$QEMU_CONF" "${QEMU_CONF}.bak"

sed -i 's/^#\(user = \).*/\1"qemu"/' "$QEMU_CONF"
sed -i 's/^#\(group = \).*/\1"qemu"/' "$QEMU_CONF"
sed -i 's/^#\(dynamic_ownership = \).*/\11/' "$QEMU_CONF"

# Ensure SELinux enforcement for sVirt VM isolation
if [ "$(getenforce)" != "Enforcing" ]; then
    setenforce 1
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
fi

systemctl restart libvirtd

# 3. Security, Privacy, and Auditing Tools
echo "[+] Purging crash reporting tools (ABRT/DrKonqi) for privacy..."
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
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/freshclam --quiet && /usr/bin/clamscan -r / --quiet --log=/var/log/clamav/scan.log") | crontab -

# 4. Flatpak and AppImage Applications
echo "[+] Installing Flatpak apps and Tuta Nota..."
flatpak install -y flathub eu.betterbird.Betterbird
flatpak install -y flathub com.bitwarden.desktop
flatpak install -y flathub com.github.wwmm.easyeffects

# PulseEffects/EasyEffects presets configuration
echo 1 | bash -c "$(curl -fsSL https://raw.githubusercontent.com/JackHack96/PulseEffects-Presets/master/install.sh)" || true

# Tutanota Desktop AppImage integration
USER_HOME=$(eval echo "~$TARGET_USER")
sudo -u "$TARGET_USER" mkdir -p "$USER_HOME/Applications" "$USER_HOME/Desktop"
sudo -u "$TARGET_USER" curl -L https://app.tuta.com/desktop/tutanota-desktop-linux.AppImage -o "$USER_HOME/Applications/tutanota.AppImage"
sudo -u "$TARGET_USER" chmod +x "$USER_HOME/Applications/tutanota.AppImage"

cat << EOF > "$USER_HOME/Desktop/Tutanota.desktop"
[Desktop Entry]
Name=Tutanota
Exec=$USER_HOME/Applications/tutanota.AppImage
Icon=mail-message-new
Type=Application
Categories=Network;Email;
Terminal=false
EOF
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/Desktop/Tutanota.desktop"
chmod +x "$USER_HOME/Desktop/Tutanota.desktop"

echo "=================================================================="
echo "[+] Complete system deployment and virtualization hardening finished!"
echo "[+] IMPORTANT: Please log out and back in (or reboot your system)"
echo "    to fully apply the libvirt/kvm user group permissions."
echo "=================================================================="
