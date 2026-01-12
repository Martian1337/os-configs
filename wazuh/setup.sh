#!/bin/bash

# References - https://groups.google.com/g/wazuh/c/RySlcql0QYM - https://documentation.wazuh.com/current/user-manual/reference/internal-options.html?monitord=#monitord

# size-based Log Cleanup Cron
( crontab -l 2>/dev/null; echo "0 2 * * * MAX=50; DIRS=\"/var/ossec/logs/{wazuh,alerts,archives,api,cluster,firewall}\"; while [ \"\$(du -sBG \$DIRS 2>/dev/null | awk '{s+=\$1} END{print s+0}')\" -gt \"\$MAX\" ]; do find \$DIRS -type f -printf '%T@ %p\n' | sort -n | head -1 | awk '{print \$2}' | xargs -r rm -f; done" ) | crontab -

# Time-based log cleanup Cron
( crontab -l 2>/dev/null; echo "0 1 * * * find /var/ossec/logs/{wazuh,alerts,archives,api,cluster,firewall} -type f -mtime +30 -delete && find /var/ossec/logs/{wazuh,alerts,archives,api,cluster,firewall} -type d -empty -delete" ) | crontab -
