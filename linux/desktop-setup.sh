#!/usr/bin/env bash
#
# Linux DESKTOP development setup, for Fedora and Ubuntu/Debian.
#
# This is the Linux counterpart to the macOS Ansible playbook in the repo root,
# deliberately much smaller. It installs GUI applications, so it is meant for a
# workstation -- a headless server wants its own script (see README.md).
#
# Installs:
#   base      curl, git, build tools, ca-certificates
#   ssh       openssh client + an ed25519 key + agent config
#   gpg       gnupg + pinentry, configured for commit signing
#   gh        GitHub CLI
#   brave     Brave browser
#   1password 1Password CLI, plus the desktop app on x86_64
#   nordvpn   NordVPN (CLI + GUI)
#   mise      mise, then Node.js LTS
#   uv        uv, then Python
#
# Usage:
#   ./desktop-setup.sh                 # everything
#   ./desktop-setup.sh --only gh,brave # just those steps
#   ./desktop-setup.sh --skip nordvpn  # everything except that
#   ./desktop-setup.sh --dry-run       # print what would run, change nothing
#
# Safe to re-run: every step checks before it acts.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly ALL_STEPS=(base ssh gpg gh brave 1password nordvpn mise uv)

# Runtime versions, kept in step with default.config.yml on the macOS side.
readonly NODE_VERSION="lts"
readonly PYTHON_VERSION="3.14"

# Published 1Password signing key. Checked after import so a swapped key on a
# hijacked mirror fails loudly instead of silently installing.
# https://support.1password.com/install-linux/
readonly ONEPASSWORD_FINGERPRINT="3FEF9748469ADBE15DA7CA80AC2D62742012EA22"
readonly ONEPASSWORD_KEY_URL="https://downloads.1password.com/linux/keys/1password.asc"
# The debsig policy directory is named after the last 16 hex of the fingerprint.
readonly ONEPASSWORD_DEBSIG_ID="AC2D62742012EA22"

readonly BRAVE_KEYRING_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
readonly BRAVE_SOURCES_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser.sources"
readonly BRAVE_RPM_REPO_URL="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"

readonly GH_KEYRING_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"
readonly GH_RPM_REPO_URL="https://cli.github.com/packages/rpm/gh-cli.repo"

# NordVPN publishes a "nordvpn-release" package that configures the repo, but
# its RPM carries no digest and RPM 4.20+ (Fedora 41+) refuses to install it.
# Its .deb also drops the key into /etc/apt/trusted.gpg.d, trusting it for every
# repo on the system. So the repo is configured directly instead. The key below
# was checked against the one inside their release package -- same fingerprint.
readonly NORDVPN_KEY_URL="https://repo.nordvpn.com/gpg/nordvpn_public.asc"
readonly NORDVPN_FINGERPRINT="BC5480EFEC5C081CE5BCFBE26B219E535C964CA1"
readonly NORDVPN_DEB_REPO="https://repo.nordvpn.com/deb/nordvpn/debian"
readonly NORDVPN_RPM_REPO="https://repo.nordvpn.com/yum/nordvpn/centos"

readonly SSH_KEY_PATH="$HOME/.ssh/id_ed25519"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
  readonly C_BLUE=$'\033[1;34m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m'
  readonly C_GREEN=$'\033[1;32m' C_DIM=$'\033[2m' C_OFF=$'\033[0m'
else
  readonly C_BLUE='' C_YELLOW='' C_RED='' C_GREEN='' C_DIM='' C_OFF=''
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
skip() { printf '%s  --%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
warn() { printf '%s==>%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

DRY_RUN=false

# Echo a command in dry-run mode, otherwise run it. Every mutating command in
# this script goes through here so --dry-run is actually trustworthy.
run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '%s     $ %s%s\n' "$C_DIM" "$*" "$C_OFF"
    return 0
  fi
  "$@"
}

# As above, but for a pipeline that has to be evaluated by a shell.
run_sh() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '%s     $ %s%s\n' "$C_DIM" "$1" "$C_OFF"
    return 0
  fi
  bash -o pipefail -c "$1"
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Distribution detection
# ---------------------------------------------------------------------------

PKG=""          # apt | dnf
DISTRO_NAME=""

detect_distro() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found -- cannot identify this distribution."

  # shellcheck disable=SC1091  # runtime file, not available at lint time
  . /etc/os-release
  DISTRO_NAME="${PRETTY_NAME:-${NAME:-unknown}}"

  case "${ID:-}" in
    fedora | rhel | centos | rocky | almalinux) PKG="dnf" ;;
    ubuntu | debian | linuxmint | pop | elementary) PKG="apt" ;;
    *)
      # Fall back to ID_LIKE for derivatives we don't name explicitly.
      case " ${ID_LIKE:-} " in
        *debian* | *ubuntu*) PKG="apt" ;;
        *fedora* | *rhel*) PKG="dnf" ;;
        *) die "Unsupported distribution: ${ID:-unknown}. This script handles Fedora and Ubuntu/Debian." ;;
      esac
      ;;
  esac

  have "$PKG" || die "Detected $PKG as the package manager, but $PKG is not on PATH."
}

# Fedora 41+ ships dnf5, whose config-manager has different syntax to dnf4's.
dnf_is_v5() {
  have dnf5 && return 0
  [[ "$(dnf --version 2>/dev/null | head -1)" == 5* ]]
}

pkg_install() {
  case "$PKG" in
    apt) run sudo apt-get install -y "$@" ;;
    dnf) run sudo dnf install -y "$@" ;;
  esac
}

pkg_refresh() {
  case "$PKG" in
    apt) run sudo apt-get update -y ;;
    dnf) : ;;  # dnf refreshes metadata on demand
  esac
}

# Is a package already installed? Used to keep steps idempotent and quiet.
pkg_installed() {
  case "$PKG" in
    apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "^install ok installed$" ;;
    dnf) rpm -q "$1" >/dev/null 2>&1 ;;
  esac
}

# Write a root-owned file from a bash variable.
#
# This exists because the obvious `echo '...' | sudo tee` form needs the content
# quoted inside a string that is itself quoted, and a $(...) in there silently
# lands in the file verbatim instead of being expanded. Interpolating in bash
# and shipping the finished bytes removes that whole class of bug.
write_root_file() {
  local dest="$1" content="$2"

  if [[ "$DRY_RUN" == true ]]; then
    printf '%s     $ write %s:%s\n' "$C_DIM" "$dest" "$C_OFF"
    printf '%s         | %s%s\n' "$C_DIM" "${content//$'\n'/$'\n'         | }" "$C_OFF"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  printf '%s\n' "$content" > "$tmp"
  sudo install -m 0644 -D "$tmp" "$dest"
  rm -f "$tmp"
}

# The Debian architecture name (amd64, arm64), used in repo definitions.
deb_arch() { dpkg --print-architecture; }

# Fetch an ASCII-armoured key and write it as a dearmoured apt keyring.
apt_add_keyring() {
  local url="$1" dest="$2"
  # Create the destination's own parent -- callers use both /etc/apt/keyrings
  # and /usr/share/keyrings, and the latter is not guaranteed to exist.
  run sudo install -d -m 0755 "$(dirname "$dest")"
  run_sh "curl -fsSL '$url' | sudo gpg --dearmor --yes --output '$dest'"
  run sudo chmod 0644 "$dest"
}

dnf_add_repo() {
  local repofile_url="$1"
  if dnf_is_v5; then
    pkg_installed dnf5-plugins || pkg_install dnf5-plugins
    run sudo dnf config-manager addrepo --overwrite --from-repofile="$repofile_url"
  else
    run sudo dnf install -y 'dnf-command(config-manager)'
    run sudo dnf config-manager --add-repo "$repofile_url"
  fi
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

step_base() {
  log "Base packages"
  pkg_refresh
  case "$PKG" in
    apt)
      pkg_install ca-certificates curl wget git gnupg apt-transport-https \
        build-essential pkg-config
      ;;
    dnf)
      pkg_install ca-certificates curl wget git gnupg2 \
        @development-tools pkgconf-pkg-config
      ;;
  esac
  ok "base packages installed"
}

step_ssh() {
  log "SSH"

  case "$PKG" in
    apt) pkg_installed openssh-client || pkg_install openssh-client ;;
    dnf) pkg_installed openssh-clients || pkg_install openssh-clients ;;
  esac

  run mkdir -p "$HOME/.ssh"
  run chmod 700 "$HOME/.ssh"

  # An existing key is never regenerated -- that would be unrecoverable.
  if [[ -f "$SSH_KEY_PATH" ]]; then
    skip "SSH key already exists at $SSH_KEY_PATH"
  else
    local comment
    local host="${HOSTNAME:-$(uname -n 2>/dev/null)}"
    comment="$(git config --get user.email 2>/dev/null || true)"
    [[ -n "$comment" ]] || comment="${USER:-$(id -un)}@${host:-localhost}"
    log "Generating an ed25519 SSH key (comment: $comment)"
    run ssh-keygen -t ed25519 -N "" -C "$comment" -f "$SSH_KEY_PATH"
    ok "SSH key generated"
  fi

  # Note there is no UseKeychain here -- that option is macOS-only and makes
  # OpenSSH on Linux abort with "Bad configuration option".
  if [[ -f "$HOME/.ssh/config" ]] && grep -q "MANAGED: linux desktop-setup" "$HOME/.ssh/config"; then
    skip "SSH client config already written"
  else
    log "Writing SSH client config"
    run_sh "cat >> '$HOME/.ssh/config' <<'EOF'

# MANAGED: linux desktop-setup
Host *
  AddKeysToAgent yes
  IdentityFile ${SSH_KEY_PATH}
  IdentitiesOnly yes

Host github.com
  HostName github.com
  User git
  IdentityFile ${SSH_KEY_PATH}
EOF"
    run chmod 600 "$HOME/.ssh/config"
  fi

  # Pin GitHub's host keys now so the first clone isn't a blind yes/no prompt.
  if [[ -f "$HOME/.ssh/known_hosts" ]] && grep -q "^github.com" "$HOME/.ssh/known_hosts" 2>/dev/null; then
    skip "github.com already in known_hosts"
  else
    run_sh "ssh-keyscan -t ed25519 github.com >> '$HOME/.ssh/known_hosts' 2>/dev/null"
  fi

  ok "SSH configured"
}

step_gpg() {
  log "GPG"

  case "$PKG" in
    apt) pkg_install gnupg pinentry-curses ;;
    dnf) pkg_install gnupg2 pinentry ;;
  esac

  run mkdir -p "$HOME/.gnupg"
  run chmod 700 "$HOME/.gnupg"

  # Without a TTY, pinentry cannot prompt and signing a commit from a terminal
  # fails with an unhelpful "Inappropriate ioctl for device".
  if [[ -f "$HOME/.gnupg/gpg-agent.conf" ]] && grep -q "MANAGED: linux desktop-setup" "$HOME/.gnupg/gpg-agent.conf"; then
    skip "gpg-agent already configured"
  else
    run_sh "cat >> '$HOME/.gnupg/gpg-agent.conf' <<'EOF'
# MANAGED: linux desktop-setup
default-cache-ttl 3600
max-cache-ttl 28800
EOF"
    run chmod 600 "$HOME/.gnupg/gpg-agent.conf"
  fi

  ok "GPG installed (import your signing key -- see README)"
}

step_gh() {
  log "GitHub CLI"

  if have gh; then
    skip "gh already installed ($(gh --version 2>/dev/null | head -1))"
    return
  fi

  case "$PKG" in
    apt)
      apt_add_keyring "$GH_KEYRING_URL" /etc/apt/keyrings/githubcli-archive-keyring.gpg
      write_root_file /etc/apt/sources.list.d/github-cli.list \
        "deb [arch=$(deb_arch) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
      pkg_refresh
      pkg_install gh
      ;;
    dnf)
      dnf_add_repo "$GH_RPM_REPO_URL"
      pkg_install gh
      ;;
  esac

  ok "gh installed"
}

step_brave() {
  log "Brave browser"

  if have brave-browser || pkg_installed brave-browser; then
    skip "Brave already installed"
    return
  fi

  case "$PKG" in
    apt)
      apt_add_keyring "$BRAVE_KEYRING_URL" /usr/share/keyrings/brave-browser-archive-keyring.gpg
      # Brave publishes a deb822 .sources file rather than a one-line list.
      run sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources "$BRAVE_SOURCES_URL"
      pkg_refresh
      pkg_install brave-browser
      ;;
    dnf)
      dnf_add_repo "$BRAVE_RPM_REPO_URL"
      pkg_install brave-browser
      ;;
  esac

  ok "Brave installed"
}

# 1Password ships the desktop app for x86_64 only; the CLI is built for both
# x86_64 and arm64. Verified against their apt repo package lists -- the arm64
# repo contains 1password-cli and nothing else. Asking for `1password` on arm64
# fails the whole transaction, so the package list is chosen by architecture.
onepassword_packages() {
  if [[ "$(uname -m)" == "x86_64" ]]; then
    printf '1password 1password-cli'
  else
    printf '1password-cli'
  fi
}

step_1password() {
  local packages
  read -r -a packages <<< "$(onepassword_packages)"

  local pkg all_present=true
  for pkg in "${packages[@]}"; do
    pkg_installed "$pkg" || all_present=false
  done

  # Check first, then announce -- otherwise a re-run repeats the arm64 warning
  # below every time even though there is nothing to install.
  if [[ "$all_present" == true ]]; then
    log "1Password"
    skip "already installed (${packages[*]})"
    return
  fi

  if [[ " ${packages[*]} " == *" 1password "* ]]; then
    log "1Password (desktop + CLI)"
  else
    log "1Password (CLI only)"
    warn "The 1Password desktop app is x86_64-only on Linux; this machine is $(uname -m)."
    warn "Installing the op CLI. For the GUI, use the 1Password extension in Brave."
  fi

  case "$PKG" in
    apt)
      apt_add_keyring "$ONEPASSWORD_KEY_URL" /usr/share/keyrings/1password-archive-keyring.gpg
      verify_keyring_fingerprint /usr/share/keyrings/1password-archive-keyring.gpg \
        "$ONEPASSWORD_FINGERPRINT" "1Password"

      write_root_file /etc/apt/sources.list.d/1password.list \
        "deb [arch=$(deb_arch) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(deb_arch) stable main"

      # debsig-verify checks the signature embedded in the .deb itself, on top
      # of the repository signature. 1Password ships a policy for it.
      run sudo install -d -m 0755 "/etc/debsig/policies/${ONEPASSWORD_DEBSIG_ID}"
      run_sh "curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol | sudo tee /etc/debsig/policies/${ONEPASSWORD_DEBSIG_ID}/1password.pol >/dev/null"
      run sudo install -d -m 0755 "/usr/share/debsig/keyrings/${ONEPASSWORD_DEBSIG_ID}"
      run_sh "curl -fsSL '$ONEPASSWORD_KEY_URL' | sudo gpg --dearmor --yes --output /usr/share/debsig/keyrings/${ONEPASSWORD_DEBSIG_ID}/debsig.gpg"

      pkg_refresh
      pkg_install "${packages[@]}"
      ;;
    dnf)
      run sudo rpm --import "$ONEPASSWORD_KEY_URL"
      # $basearch is expanded by dnf itself, so it stays literal here.
      write_root_file /etc/yum.repos.d/1password.repo "[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${ONEPASSWORD_KEY_URL}"
      pkg_install "${packages[@]}"
      ;;
  esac

  ok "1Password installed (${packages[*]})"
}

# Confirm an imported key really is the vendor's, not something a compromised
# mirror handed us. Cheap, and a repo's entire trust chain rests on its key.
verify_keyring_fingerprint() {
  local keyring="$1" expected="$2" label="$3"
  [[ "$DRY_RUN" == true ]] && return 0

  local found
  found="$(gpg --show-keys --with-colons "$keyring" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
  if [[ "$found" != "$expected" ]]; then
    die "${label} key fingerprint mismatch.
  expected: ${expected}
  got:      ${found:-<none>}
Refusing to add the repository."
  fi
  ok "${label} key fingerprint verified"
}

step_nordvpn() {
  log "NordVPN"

  if have nordvpn; then
    skip "NordVPN already installed ($(nordvpn --version 2>/dev/null | head -1))"
    return
  fi

  case "$PKG" in
    apt)
      apt_add_keyring "$NORDVPN_KEY_URL" /usr/share/keyrings/nordvpn-keyring.gpg
      verify_keyring_fingerprint /usr/share/keyrings/nordvpn-keyring.gpg \
        "$NORDVPN_FINGERPRINT" "NordVPN"
      write_root_file /etc/apt/sources.list.d/nordvpn.list \
        "deb [arch=$(deb_arch) signed-by=/usr/share/keyrings/nordvpn-keyring.gpg] ${NORDVPN_DEB_REPO} stable main"
      pkg_refresh
      pkg_install nordvpn
      ;;
    dnf)
      run sudo rpm --import "$NORDVPN_KEY_URL"
      # $basearch is expanded by dnf itself, so it stays literal here.
      write_root_file /etc/yum.repos.d/nordvpn.repo "[nordvpn]
name=NordVPN
baseurl=${NORDVPN_RPM_REPO}/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${NORDVPN_KEY_URL}"
      pkg_install nordvpn
      ;;
  esac

  # Without this, every nordvpn command fails with a permissions error.
  if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx nordvpn; then
    skip "already in the nordvpn group"
  else
    run sudo usermod -aG nordvpn "$USER"
    warn "Added you to the 'nordvpn' group -- log out and back in before using it."
  fi

  ok "NordVPN installed"
}

step_mise() {
  log "mise + Node.js"

  local mise_bin="$HOME/.local/bin/mise"

  if have mise; then
    mise_bin="$(command -v mise)"
    skip "mise already installed ($("$mise_bin" --version 2>/dev/null | head -1))"
  else
    run_sh "curl -fsSL https://mise.run | sh"
  fi

  # mise is not on PATH yet in this shell, so call it by absolute path.
  if [[ "$DRY_RUN" == false && ! -x "$mise_bin" ]]; then
    die "mise did not install to $mise_bin"
  fi

  # `mise use` has no --yes flag; it installs non-interactively on its own.
  run "$mise_bin" use --global "node@${NODE_VERSION}"
  ok "Node.js ${NODE_VERSION} installed via mise"
}

step_uv() {
  log "uv + Python"

  local uv_bin="$HOME/.local/bin/uv"

  if have uv; then
    uv_bin="$(command -v uv)"
    skip "uv already installed ($("$uv_bin" --version 2>/dev/null | head -1))"
  else
    run_sh "curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi

  if [[ "$DRY_RUN" == false && ! -x "$uv_bin" ]]; then
    die "uv did not install to $uv_bin"
  fi

  # --default creates the bare `python`/`python3` symlinks in ~/.local/bin;
  # without it you only get versioned names like python3.14.
  run "$uv_bin" python install --default "$PYTHON_VERSION"
  ok "Python ${PYTHON_VERSION} installed via uv"
}

# ---------------------------------------------------------------------------
# Post-run summary
# ---------------------------------------------------------------------------

summary() {
  local pubkey="${SSH_KEY_PATH}.pub"

  cat <<EOF

${C_GREEN}Done.${C_OFF} ${DISTRO_NAME}

Still needs you:

  1. Add ~/.local/bin to PATH if it isn't already, then restart your shell:
       export PATH="\$HOME/.local/bin:\$PATH"
       eval "\$(mise activate bash)"    # or zsh

  2. Sign in to 1Password, and to gh:
       gh auth login

  3. Add your SSH key to GitHub:
       gh ssh-key add ${pubkey} --title "\$(hostname)"
EOF

  if [[ -f "$pubkey" ]]; then
    printf '\n     Your public key:\n     %s\n' "$(cat "$pubkey")"
  fi

  cat <<EOF

  4. Import your GPG signing key (export it from the machine that has it):
       gpg --import private.key
       git config --global user.signingkey <KEY_ID>

  5. Log in to NordVPN:
       nordvpn login

  6. Log out and back in for the 'nordvpn' group to take effect.

EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

# Print this file's header comment block as the help text, so the docs at the
# top of the script and `--help` can never drift apart.
usage() {
  awk '
    NR == 1 && /^#!/ { next }          # skip the shebang
    /^#/              { sub(/^# ?/, ""); print; next }
    /^[[:space:]]*$/  { print; next }
    { exit }                            # first line of real code ends the block
  ' "$0"
  exit "${1:-0}"
}

main() {
  local only="" skipped=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only) only="${2:-}"; shift 2 || die "--only needs a value" ;;
      --only=*) only="${1#*=}"; shift ;;
      --skip) skipped="${2:-}"; shift 2 || die "--skip needs a value" ;;
      --skip=*) skipped="${1#*=}"; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h | --help) usage 0 ;;
      *) die "Unknown option: $1 (try --help)" ;;
    esac
  done

  [[ "$(uname -s)" == "Linux" ]] || die "This script is for Linux. On macOS, use the Ansible playbook in the repo root."
  [[ "$(id -u)" != "0" ]] || die "Don't run this as root -- it calls sudo where it needs to, and files in \$HOME should belong to you."

  detect_distro
  log "Detected ${DISTRO_NAME} (package manager: ${PKG})"

  # Stop dpkg opening a curses config dialog part-way through an unattended
  # install and blocking on input nobody is there to give.
  if [[ "$PKG" == "apt" ]]; then
    export DEBIAN_FRONTEND=noninteractive
  fi

  # Validate step names before doing any work, so a typo doesn't silently
  # install nothing or install everything.
  local requested=()
  if [[ -n "$only" ]]; then
    IFS=',' read -r -a requested <<< "$only"
  else
    requested=("${ALL_STEPS[@]}")
  fi

  local -a skip_list=()
  [[ -n "$skipped" ]] && IFS=',' read -r -a skip_list <<< "$skipped"

  local name
  for name in "${requested[@]}" "${skip_list[@]+"${skip_list[@]}"}"; do
    [[ " ${ALL_STEPS[*]} " == *" $name "* ]] \
      || die "Unknown step: '$name'. Valid steps: ${ALL_STEPS[*]}"
  done

  if [[ "$DRY_RUN" == true ]]; then
    warn "Dry run -- printing commands, changing nothing."
  else
    # Prompt for sudo once, up front, rather than halfway through a download.
    log "Caching sudo credentials"
    sudo -v || die "sudo is required."
  fi

  if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" && "$DRY_RUN" == false ]]; then
    warn "No display server detected. This script installs desktop apps (Brave,"
    warn "1Password, NordVPN GUI). On a headless box, use --skip brave,1password."
  fi

  local step
  for step in "${requested[@]}"; do
    if [[ " ${skip_list[*]+"${skip_list[*]}"} " == *" $step "* ]]; then
      skip "skipping $step"
      continue
    fi
    "step_${step}"
  done

  summary
}

main "$@"
