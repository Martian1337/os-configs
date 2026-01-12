#!/bin/bash

# These can also be set via KDE System Settings GUI

# Disable tracking of recent files
kwriteconfig5 --file recentdocumentsrc --group RecentDocuments --key MaxEntries 0
# Disable screen blanking (set to never)
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Timeout 0
kwriteconfig5 --file kscreensaverrc --group ScreenSaver --key Lock false
# Show hidden files in Dolphin file manager
kwriteconfig5 --file dolphinrc --group General --key ShowHiddenFiles true
# Enable "Delete Permanently" option in Dolphin
kwriteconfig5 --file dolphinrc --group General --key ConfirmDelete false
