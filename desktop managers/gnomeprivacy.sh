#!/bin/bash

# Disable diagnostics reporting
gsettings set com.ubuntu.update-notifier show-apport-crashes false
gsettings set org.gnome.desktop.notifications show-in-lock-screen false

# Disable tracking of recent files
gsettings set org.gnome.desktop.privacy remember-recent-files false

# Turning off the screen blank
gsettings set org.gnome.desktop.session idle-delay 0

# Disable automatic screen locking
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend false

# Permanently delete an object without moving it to the trash
gsettings set org.gnome.nautilus.preferences show-delete-permanently true

# Show hidden files
gsettings set org.gnome.nautilus.preferences show-hidden-files true
