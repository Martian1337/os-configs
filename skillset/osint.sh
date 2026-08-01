#!/usr/bin/env bash

set -euo pipefail

[[ $EUID -eq 0 ]] && { echo "Run as a regular user with sudo, not as root."; exit 1; }

WORKDIR="${HOME}/osint"
mkdir -p "$WORKDIR" && cd "$WORKDIR"

# --- prerequisites -----------------------------------------------------------
# zsh is required: tlosint-tools.sh has a #!/bin/zsh shebang
sudo apt update
sudo apt install -y git curl wget ca-certificates zsh build-essential

# OSINT VM Toolset
wget -q https://raw.githubusercontent.com/tracelabs/tlosint-vm/main/scripts/tlosint-tools.sh
chmod +x tlosint-tools.sh
./tlosint-tools.sh

# ReconFTW
if [[ -d reconftw/.git ]]; then
  git -C reconftw pull --ff-only
else
  git clone --depth 1 https://github.com/six2dez/reconftw
fi
(cd reconftw && ./install.sh --verbose)
cd "$WORKDIR"

# Tooling Gaps
sudo apt install -y \
  theharvester recon-ng dnsrecon whatweb wafw00f dnstwist \
  yt-dlp mat2 poppler-utils imagemagick pandoc \
  proxychains4 torsocks keepassxc \
  csvkit sqlite3 graphviz

# pipx apps (idempotent: install or upgrade)
for app in maigret holehe h8mail ignorant socialscan instaloader \
           gallery-dl visidata ghunt toutatis onionsearch; do
  if pipx list 2>/dev/null | grep -qi "package ${app} "; then
    pipx upgrade "$app" || true
  else
    pipx install "$app" || echo "WARN: pipx install ${app} failed (continuing)"
  fi
done

# Rust: single-file page archival for evidence capture
command -v monolith >/dev/null 2>&1 || cargo install monolith

# Go: takeover detection + URL harvesting
command -v subjack >/dev/null 2>&1 || \
  env GOBIN=/usr/local/bin sudo -E go install github.com/haccer/subjack@latest
command -v gau >/dev/null 2>&1 || \
  env GOBIN=/usr/local/bin sudo -E go install github.com/lc/gau/v2/cmd/gau@latest

# --- done --------------------------------------------------------------------
cat <<'EOF'

Install complete. Before first use:

  reconftw   ~/Tools/reconftw/reconftw.cfg   — Shodan, Censys, GitHub, etc.
  shodan     shodan init <API_KEY>
  h8mail     ~/.config/h8mail/h8mail_config.ini — HIBP / Dehashed
  ghunt      ghunt login  (requires browser cookie export)
  recon-ng   recon-cli -w default, then 'keys add <name> <value>'

Logs:
  tlosint    ~/osint-bootstrap.log
  updater    /var/log/osint-updater.log

Re-run tlosint validation only:  ./tlosint-tools.sh --validate-only
System + tool update:           pkexec /usr/local/bin/osint-updater
EOF
