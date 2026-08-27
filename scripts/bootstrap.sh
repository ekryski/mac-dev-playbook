#!/usr/bin/env bash
#
# Bootstraps a brand-new Mac to the point where the Ansible playbook can run.
#
# Everything here is the bare minimum that cannot be done from Ansible itself,
# because Ansible is one of the things it installs:
#
#   1. Xcode Command Line Tools (needed by Homebrew)
#   2. Homebrew
#   3. git + ansible
#   4. this repository
#   5. the Galaxy collections the playbook depends on
#
# Usage, on a fresh machine:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ekryski/mac-dev-playbook/main/scripts/bootstrap.sh)"

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ekryski/mac-dev-playbook.git}"
REPO_DEST="${REPO_DEST:-$HOME/Development/personal/mac-dev-playbook}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script only runs on macOS."

# ---------------------------------------------------------------------------
# 1. Xcode Command Line Tools
# ---------------------------------------------------------------------------
if xcode-select --print-path >/dev/null 2>&1; then
  log "Xcode Command Line Tools already installed."
else
  log "Installing Xcode Command Line Tools..."
  xcode-select --install || true
  warn "Finish the Command Line Tools installer in the GUI, then press Return."
  read -r
  xcode-select --print-path >/dev/null 2>&1 \
    || die "Command Line Tools still missing. Install them and re-run this script."
fi

# ---------------------------------------------------------------------------
# 2. Homebrew
# ---------------------------------------------------------------------------
# Apple Silicon puts Homebrew in /opt/homebrew; Intel keeps it in /usr/local.
if [[ "$(uname -m)" == "arm64" ]]; then
  HOMEBREW_PREFIX="/opt/homebrew"
else
  HOMEBREW_PREFIX="/usr/local"
fi

if [[ -x "${HOMEBREW_PREFIX}/bin/brew" ]]; then
  log "Homebrew already installed at ${HOMEBREW_PREFIX}."
else
  log "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

eval "$("${HOMEBREW_PREFIX}/bin/brew" shellenv)"

# ---------------------------------------------------------------------------
# 3. git + ansible
# ---------------------------------------------------------------------------
log "Installing git and ansible..."
brew install git ansible

# ---------------------------------------------------------------------------
# 4. The playbook itself
# ---------------------------------------------------------------------------
if [[ -d "${REPO_DEST}/.git" ]]; then
  log "Playbook already cloned at ${REPO_DEST}."
else
  log "Cloning ${REPO_URL} to ${REPO_DEST}..."
  mkdir -p "$(dirname "${REPO_DEST}")"
  git clone "${REPO_URL}" "${REPO_DEST}"
fi

cd "${REPO_DEST}"

# ---------------------------------------------------------------------------
# 5. Galaxy collections
# ---------------------------------------------------------------------------
log "Installing Ansible collections..."
ansible-galaxy install -r requirements.yml

cat <<EOF

Bootstrap complete.

Next:
  cd ${REPO_DEST}
  cp config.example.yml config.yml   # optional: override anything you like
  ansible-playbook main.yml --ask-become-pass

EOF
