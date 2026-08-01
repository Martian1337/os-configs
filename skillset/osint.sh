#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Run as a regular user with sudo, not as root." >&2
  exit 1
fi

WORKDIR="${HOME}/osint"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Cache sudo credentials up front so the long unattended stretches don't stall
# on a password prompt after the terminal has scrolled away.
sudo -v

# --- prerequisites -----------------------------------------------------------
# zsh is required: tlosint-tools.sh has a #!/bin/zsh shebang
sudo apt update
sudo apt install -y git curl wget ca-certificates zsh build-essential pipx

# --- OSINT VM Toolset --------------------------------------------------------
wget -q -O tlosint-tools.sh \
  https://raw.githubusercontent.com/tracelabs/tlosint-vm/main/scripts/tlosint-tools.sh
chmod +x tlosint-tools.sh
./tlosint-tools.sh

# tlosint appends PATH entries to the shell profiles, but those don't apply to the shell we're already in. Everything below needs them live, now.
# shellcheck disable=SC1091
[[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env"
export GOPATH="${GOPATH:-${HOME}/go}"
export PATH="${HOME}/.local/bin:${GOPATH}/bin:${HOME}/.cargo/bin:/usr/local/bin:${PATH}"
hash -r

# --- ReconFTW ---------------------------------------------------------------
if [[ -d reconftw/.git ]]; then
  git -C reconftw pull --ff-only
else
  git clone --depth 1 https://github.com/six2dez/reconftw
fi
(cd reconftw && ./install.sh --verbose)
cd "$WORKDIR"

# Tooling gaps
APT_TOOLS=(
  theharvester recon-ng dnsrecon whatweb wafw00f dnstwist
  yt-dlp mat2 poppler-utils imagemagick pandoc
  proxychains4 torsocks keepassxc
  csvkit sqlite3 graphviz
)
APT_MISSING=()
for pkg in "${APT_TOOLS[@]}"; do
  sudo apt install -y "$pkg" || APT_MISSING+=("$pkg")
done

# recon-ng is frequently absent outside Kali; fall back to a source install.
if ! command -v recon-ng >/dev/null 2>&1; then
  echo "[*] recon-ng not in repos; installing from source into /opt"
  if [[ -d /opt/recon-ng/.git ]]; then
    sudo git -C /opt/recon-ng pull --ff-only || true
  else
    sudo git clone --depth 1 https://github.com/lanmaster53/recon-ng /opt/recon-ng
  fi
  sudo python3 -m venv /opt/recon-ng/venv
  sudo /opt/recon-ng/venv/bin/pip -q install --upgrade pip wheel setuptools
  sudo /opt/recon-ng/venv/bin/pip -q install -r /opt/recon-ng/REQUIREMENTS
  for entry in recon-ng recon-cli; do
    sudo tee "/usr/local/bin/${entry}" >/dev/null <<EOF
#!/usr/bin/env bash
exec /opt/recon-ng/venv/bin/python3 /opt/recon-ng/${entry}.py "\$@"
EOF
    sudo chmod 0755 "/usr/local/bin/${entry}"
  done
  # Drop it from the missing list now that it's handled.
  for i in "${!APT_MISSING[@]}"; do
    [[ "${APT_MISSING[$i]}" == "recon-ng" ]] && unset 'APT_MISSING[i]'
  done
fi

# pipx
command -v pipx >/dev/null 2>&1 || python3 -m pip install --user -U pipx
pipx ensurepath >/dev/null 2>&1 || true

PIPX_APPS=(
  maigret holehe h8mail ignorant socialscan instaloader
  gallery-dl visidata ghunt toutatis onionsearch
)
PIPX_MISSING=()
for app in "${PIPX_APPS[@]}"; do
  if pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx "$app"; then
    pipx upgrade "$app" || true
  else
    pipx install "$app" || PIPX_MISSING+=("$app")
  fi
done

# Rust
command -v monolith >/dev/null 2>&1 || cargo install --locked monolith

# Go
go_get() {
  local module="$1" bin="$2"
  command -v "$bin" >/dev/null 2>&1 && return 0
  go install "$module" || { echo "WARN: go install ${bin} failed" >&2; return 0; }
  [[ -x "${GOPATH}/bin/${bin}" ]] && sudo install -m 0755 "${GOPATH}/bin/${bin}" "/usr/local/bin/${bin}"
}
if command -v go >/dev/null 2>&1; then
  go_get github.com/haccer/subjack@latest subjack
  go_get github.com/lc/gau/v2/cmd/gau@latest gau
else
  echo "WARN: go not on PATH; skipped subjack and gau" >&2
fi

# Summary
echo
if (( ${#APT_MISSING[@]} )); then
  echo "WARN: not available via apt, install manually: ${APT_MISSING[*]}"
fi
if (( ${#PIPX_MISSING[@]} )); then
  echo "WARN: pipx install failed for: ${PIPX_MISSING[*]}"
fi

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

Re-run tlosint validation only:  ~/osint/tlosint-tools.sh --validate-only
System + tool update:           pkexec /usr/local/bin/osint-updater

Log out and back in before first use — docker group membership, GOBIN, and
~/.local/bin are written to your shell profiles and won't be live until then.
EOF
