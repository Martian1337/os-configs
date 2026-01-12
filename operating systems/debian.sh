#!/bin/bash
set -e

# Install core dependencies
sudo apt install -y snapd flatpak curl wget software-properties-common apt-transport-https

# Enable snapd socket
sudo systemctl enable --now snapd.socket
sudo ln -s /var/lib/snapd/snap /snap # Ensure snap command works

# Add Flathub repository for Flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Mullvad VPN repository and installation
curl -fsSLo /usr/share/keyrings/mullvad-archive-keyring.gpg https://repository.mullvad.net/deb/mullvad-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/mullvad-archive-keyring.gpg] https://repository.mullvad.net/deb stable main" | sudo tee /etc/apt/sources.list.d/mullvad.list
sudo apt update
sudo apt install -y mullvad-vpn

# ProtonVPN repository and installation
curl -fsSL https://repo.protonvpn.com/debian/public_key.asc | sudo tee /usr/share/keyrings/protonvpn.asc
echo "deb [signed-by=/usr/share/keyrings/protonvpn.asc] https://repo.protonvpn.com/debian stable main" | sudo tee /etc/apt/sources.list.d/protonvpn.list
sudo apt update
sudo apt install -y protonvpn protonvpn-cli protonvpn-gui

# Install Brave Browser
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update
sudo apt install -y brave-browser

# Install LibreWolf browser
sudo curl -fsSL https://deb.librewolf.net/keyring.gpg | sudo tee /usr/share/keyrings/librewolf.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/librewolf.gpg] https://deb.librewolf.net/ stable main" | sudo tee /etc/apt/sources.list.d/librewolf.list
sudo apt update
sudo apt install -y librewolf

# Install VSCodium
wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/vscodium.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/vscodium.gpg] https://download.vscodium.com/debs vscodium main" | sudo tee /etc/apt/sources.list.d/vscodium.list
sudo apt update
sudo apt install -y codium

# Install BetterBird flatpak email client
wget https://dl.flathub.org/repo/appstream/eu.betterbird.Betterbird.flatpakref
flatpak install --assumeyes eu.betterbird.Betterbird.flatpakref
rm eu.betterbird.Betterbird.flatpakref

# Install Virt-manager and start libvirt service
sudo apt install -y virt-manager libvirt-daemon-system libvirt-clients qemu-kvm
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm $USER

sudo curl -so /etc/apt/trusted.gpg.d/oxen.gpg https://deb.oxen.io/pub.gpg
echo "deb https://deb.oxen.io $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/oxen.list
sudo apt update 
sudo apt install lokinet lokinet-gui

# Privacy and Security Hardening
# Turning off problem reporting
sudo apt purge apport apport-symptoms popularity-contest ubuntu-report whoopsie -y
sudo rm /etc/update-motd.d/50-motd-news
# Install security tools
sudo apt install -y lynis fail2ban bleachbit mat2 clamav clamtk
# Update ClamAV virus definitions and enable service
sudo systemctl stop clamav-freshclam.service || true
sudo freshclam
sudo systemctl enable --now clamav-freshclam.service fail2ban

# Install Bitwarden (flatpak)
flatpak install --assumeyes flathub com.bitwarden.desktop

# Set up cron jobs for regular scans and audits
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/lynis audit system --cronjob >> /var/log/lynis.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/freshclam --quiet && /usr/bin/clamscan -r / --quiet --log=/var/log/clamav/scan.log") | crontab -

# Install TutaNota Binary
mkdir -p ~/Applications ~/Desktop && curl -L https://app.tuta.com/desktop/tutanota-desktop-linux.AppImage -o ~/Applications/tutanota.AppImage && chmod +x ~/Applications/tutanota.AppImage && echo -e "[Desktop Entry]\nName=Tutanota\nExec=$HOME/Applications/tutanota.AppImage\nIcon=mail-message-new\nType=Application\nCategories=Network;Email;\nTerminal=false" > ~/Desktop/Tutanota.desktop && chmod +x ~/Desktop/Tutanota.desktop

# Install EasyEffects (flatpak)
flatpak install --assumeyes flathub com.github.wwmm.easyeffects
bash -c "$(curl -fsSL https://raw.githubusercontent.com/JackHack96/PulseEffects-Presets/master/install.sh)" <<< "1"

echo "Reminder: Please log out and log back in to apply group changes (libvirt and kvm)."
