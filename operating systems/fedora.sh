#!/bin/bash

# Install Snap and flatpak
sudo dnf install -y snapd flatpak
sudo systemctl enable --now snapd.socket
sudo ln -s /usr/lib/snapd/snap /usr/bin/snap # Ensure snap command works after install
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Mullvad VPN repository and installation
sudo dnf config-manager --add-repo=https://repository.mullvad.net/rpm/stable/mullvad.repo
sudo dnf install -y mullvad-vpn

# ProtonVPN repository and installation
fedora_version=$(rpm -E %fedora)
wget "https://repo.protonvpn.com/fedora-${fedora_version}-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.3-1.noarch.rpm"
sudo dnf install -y ./protonvpn-stable-release-1.0.3-1.noarch.rpm proton-vpn-gnome-desktop libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app openresolv
rm -f protonvpn-stable-release-1.0.3-1.noarch.rpm
sudo dnf check-update --refresh
sudo wget "https://raw.githubusercontent.com/ProtonVPN/scripts/master/update-resolv-conf.sh" -O "/etc/openvpn/update-resolv-conf"
sudo chmod +x "/etc/openvpn/update-resolv-conf"

# Install Brave Browser
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo=https://brave-browser-rpm-release.s3.brave.com/x86_64/

# Install LibreWolf repository and package
curl -fsSL https://repo.librewolf.net/librewolf.repo | sudo tee /etc/yum.repos.d/librewolf.repo
sudo dnf install -y librewolf

# Install VSCodium
sudo rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=download.vscodium.com\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg\nmetadata_expire=1h\n" | sudo tee -a /etc/yum.repos.d/vscodium.repo
sudo dnf install codium

# Install BetterBird (email)
wget https://dl.flathub.org/repo/appstream/eu.betterbird.Betterbird.flatpakref
flatpak install eu.betterbird.Betterbird.flatpakref

# Install Virt-manager
sudo dnf install virt-manager
sudo systemctl start libvirtd
sudo usermod -aG libvirt,kvm $USER # Add current user to libvirt and kvm groups for non-sudo access

# Install Lokinet
sudo dnf config-manager --add-repo https://rpm.oxen.io/fedora/oxen.repo   
sudo dnf install lokinet
sudo systemctl enable lokinet --now
# sudo rpmkeys --import https://rpm.oxen.io/public.gpg && etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-37-$(arch) && sudo dnf config-manager addrepo --from-repofile=https://rpm.oxen.io/fedora/oxen.repo   
# sudo dnf install lokinet --enable-repo=oxen --releasever=37
# sudo systemctl enable lokinet.service --now


# Privacy and Security Hardening
# System crash and problem reporting
sudo systemctl disable --now abrtd.service abrt-ccpp.service && sudo dnf remove -y abrt # Disable and remove ABRT 
sudo dnf remove -y drkonqi # Remove KDE crash handler DrKonqi
# Install system security tools
sudo dnf install lynis fail2ban bleachbit mat2 clamav clamd clamav-update clamtk -y
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl enable --now fail2ban clamav-freshclam.service
flatpak install flathub com.bitwarden.desktop


# Set up Cron job for regular system scans and hardening
(sudo crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/lynis audit system --cronjob >> /var/log/lynis.log 2>&1") | sudo crontab - # Lynis Daily at 2 AM
(sudo crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/freshclam --quiet && /usr/bin/clamscan -r / --quiet --log=/var/log/clamav/scan.log") | sudo crontab - # ClamAV scan Daily at 3 AM
# (sudo crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/lynis audit system --cronjob >> /var/log/lynis.log 2>&1 && /usr/bin/freshclam --quiet && /usr/bin/clamscan -r / --quiet --log=/var/log/clamav/scan.log") | sudo crontab - # All 3 scans combined Daily at 2 AM (Resource intensive) 

# Install TutaNota Binary
mkdir -p ~/Applications ~/Desktop && curl -L https://app.tuta.com/desktop/tutanota-desktop-linux.AppImage -o ~/Applications/tutanota.AppImage && chmod +x ~/Applications/tutanota.AppImage && echo -e "[Desktop Entry]\nName=Tutanota\nExec=$HOME/Applications/tutanota.AppImage\nIcon=mail-message-new\nType=Application\nCategories=Network;Email;\nTerminal=false" > ~/Desktop/Tutanota.desktop && chmod +x ~/Desktop/Tutanota.desktop

# Install EasyEffects
flatpak install flathub com.github.wwmm.easyeffects
echo 1 | bash -c "$(curl -fsSL https://raw.githubusercontent.com/JackHack96/PulseEffects-Presets/master/install.sh)"


# Reminder
echo "Reminder: Please log out and log back in to apply user group changes (for Virt-manager and KVM)."
