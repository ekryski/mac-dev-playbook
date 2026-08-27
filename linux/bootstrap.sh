#!/usr/bin/env bash
#
# Bootstrap a brand-new Linux desktop, from nothing to a cloned repo.
#
# Solves the chicken-and-egg problem: you cannot clone your repos until GitHub
# trusts this machine, you cannot authenticate with GitHub until you can read
# your credentials, and your credentials are in 1Password, which is not
# installed yet. So this runs in dependency order:
#
#   1. minimal packages (curl, git, gnupg)
#   2. 1Password       -- then you sign in
#   3. GitHub CLI      -- then you sign in, reading credentials from 1Password
#   4. SSH key         -- generated and uploaded to GitHub automatically
#   5. clone the repo  -- over SSH, so private repos work
#   6. hand off to desktop-setup.sh for everything else
#
# Run it with:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ekryski/mac-dev-playbook/main/linux/bootstrap.sh)"
#
# Use that form, NOT `curl ... | bash`. Piping makes the script itself bash's
# stdin, so the interactive 1Password and GitHub sign-in prompts would try to
# read the script text instead of your keyboard. With `bash -c "$(...)"` the
# script arrives as an argument and stdin stays attached to your terminal.
#
# Options:
#   --repo-dir DIR   where to clone (default ~/Development/personal/mac-dev-playbook)
#   --skip-setup     stop after cloning; don't run desktop-setup.sh
#   --dry-run        print what would happen, change nothing
#
# Environment:
#   REPO_REF         branch to pull from and clone (default main)

set -euo pipefail

readonly REPO_SLUG="ekryski/mac-dev-playbook"
readonly REPO_SSH="git@github.com:${REPO_SLUG}.git"

# Which branch to pull desktop-setup.sh from. Override to bootstrap-test a
# branch before merging it:  REPO_REF=my-branch bash -c "$(curl ...)"
REPO_REF="${REPO_REF:-main}"
readonly REPO_RAW="https://raw.githubusercontent.com/${REPO_SLUG}/${REPO_REF}"

REPO_DIR="${REPO_DIR:-$HOME/Development/personal/mac-dev-playbook}"
SKIP_SETUP=false
DRY_RUN=false

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
  readonly C_BLUE=$'\033[1;34m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m'
  readonly C_GREEN=$'\033[1;32m' C_BOLD=$'\033[1m' C_OFF=$'\033[0m'
else
  readonly C_BLUE='' C_YELLOW='' C_RED='' C_GREEN='' C_BOLD='' C_OFF=''
fi

log()  { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%s==>%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Interaction
#
# Everything interactive reads from /dev/tty explicitly rather than stdin. That
# keeps the script working even if someone ignores the warning above and pipes
# it into bash, where stdin is the script text rather than the keyboard.
# ---------------------------------------------------------------------------

# Test by actually opening /dev/tty. `[[ -r /dev/tty ]]` is not good enough:
# it uses access(2), which reports the device node's permissions and says
# "readable" even when the process has no controlling terminal at all.
TTY_AVAILABLE=false
if { : < /dev/tty; } 2>/dev/null; then
  TTY_AVAILABLE=true
fi

pause() {
  local message="$1"
  printf '\n%s%s%s\n' "$C_YELLOW" "$message" "$C_OFF"
  if [[ "$DRY_RUN" == true ]]; then
    printf '     (dry run -- not waiting)\n'
    return 0
  fi
  printf '     Press Return when done, or Ctrl-C to stop here. '
  read -r _ < /dev/tty || true
  printf '\n'
}

confirm() {
  local message="$1" reply
  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi
  printf '%s [y/N] ' "$message"
  read -r reply < /dev/tty || reply=""
  [[ "$reply" =~ ^[Yy] ]]
}

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '     $ %s\n' "$*"
    return 0
  fi
  "$@"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

usage() {
  awk '
    NR == 1 && /^#!/ { next }
    /^#/              { sub(/^# ?/, ""); print; next }
    /^[[:space:]]*$/  { print; next }
    { exit }
  ' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir) REPO_DIR="${2:-}"; shift 2 || die "--repo-dir needs a value" ;;
    --repo-dir=*) REPO_DIR="${1#*=}"; shift ;;
    --skip-setup) SKIP_SETUP=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h | --help) usage 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "This bootstrap is for Linux. On macOS use scripts/bootstrap.sh."
[[ "$(id -u)" != "0" ]] || die "Don't run this as root; it calls sudo where it needs to."

if [[ "$TTY_AVAILABLE" == false && "$DRY_RUN" == false ]]; then
  die "No terminal available, and signing in to 1Password and GitHub needs one.
Run this from an interactive shell:
  bash -c \"\$(curl -fsSL ${REPO_RAW}/linux/bootstrap.sh)\""
fi

# ---------------------------------------------------------------------------
# Fetch the worker script
#
# desktop-setup.sh does all the actual installing. Downloading it rather than
# duplicating its logic means there is exactly one definition of how each
# package gets installed.
# ---------------------------------------------------------------------------

WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2317  # invoked via trap
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

SETUP="$WORK_DIR/desktop-setup.sh"

fetch_setup_script() {
  log "Fetching desktop-setup.sh"
  have curl || die "curl is required to bootstrap. Install it and re-run."
  curl -fsSL "${REPO_RAW}/linux/desktop-setup.sh" -o "$SETUP" \
    || die "Could not download desktop-setup.sh from ${REPO_RAW}"
  chmod +x "$SETUP"
  bash -n "$SETUP" || die "Downloaded desktop-setup.sh failed to parse."
  ok "downloaded"
}

# Run one or more steps of desktop-setup.sh.
setup_steps() {
  local steps="$1"
  local args=(--only "$steps")
  [[ "$DRY_RUN" == true ]] && args+=(--dry-run)
  "$SETUP" "${args[@]}"
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

step_packages() {
  log "Step 1/6 -- base packages"
  setup_steps base
}

step_1password() {
  log "Step 2/6 -- 1Password"
  setup_steps 1password

  if [[ "$DRY_RUN" == false ]] && op_is_signed_in; then
    ok "1Password CLI is already signed in"
    return 0
  fi

  # Two ways in. The desktop app path is nicer but is x86_64-only; on arm64
  # `op account add` is the only option.
  if [[ "$(uname -m)" == "x86_64" ]]; then
    pause "Sign in to 1Password now:
       1. Open the 1Password app and sign in.
       2. Settings > Developer > tick 'Integrate with 1Password CLI'.
     Or, if you'd rather stay in the terminal, run:  op account add"
  else
    pause "Sign in to 1Password now. There is no desktop app for $(uname -m),
     so use the CLI:  op account add
     You'll need your account's sign-in address, email and Secret Key."
  fi

  if [[ "$DRY_RUN" == false ]] && ! op_is_signed_in; then
    warn "1Password CLI still isn't signed in."
    confirm "Carry on anyway? You'll need your GitHub credentials another way." \
      || die "Stopping. Sign in to 1Password, then re-run this script."
  else
    ok "1Password ready"
  fi
}

op_is_signed_in() {
  have op || return 1
  op account list >/dev/null 2>&1
}

step_gh() {
  log "Step 3/6 -- GitHub CLI"
  setup_steps gh

  if [[ "$DRY_RUN" == true ]]; then
    printf '     $ gh auth login\n'
    return 0
  fi

  if gh auth status >/dev/null 2>&1; then
    ok "gh is already signed in"
    return 0
  fi

  cat <<EOF

     About to run: gh auth login

     Pick 'GitHub.com', then 'HTTPS', then either:
       - 'Login with a web browser' -- easiest if you have a browser here
       - 'Paste an authentication token' -- read it out of 1Password with:
             op read "op://Private/GitHub/token"
         The token needs the 'admin:public_key' scope so this script can
         upload your SSH key, plus 'repo' for private repositories.

EOF
  pause "Ready to sign in to GitHub?"

  # Interactive, and it needs the real terminal on both ends.
  gh auth login < /dev/tty > /dev/tty 2>&1 || die "gh auth login did not complete."

  gh auth status >/dev/null 2>&1 || die "gh still isn't signed in."
  ok "signed in to GitHub as $(gh api user --jq .login 2>/dev/null || echo 'unknown')"
}

step_ssh() {
  log "Step 4/6 -- SSH key"
  # desktop-setup.sh generates the key and, because gh is now signed in,
  # uploads it to GitHub in the same step.
  setup_steps ssh
}

step_clone() {
  log "Step 5/6 -- clone ${REPO_SLUG}"

  if [[ -d "$REPO_DIR/.git" ]]; then
    ok "already cloned at $REPO_DIR"
    return 0
  fi

  run mkdir -p "$(dirname "$REPO_DIR")"

  if [[ "$DRY_RUN" == true ]]; then
    printf '     $ git clone %s %s\n' "$REPO_SSH" "$REPO_DIR"
    return 0
  fi

  # Confirms the whole chain works: the key exists, GitHub has it, and the
  # agent is using it. Falls back to gh, which authenticates over HTTPS and so
  # still reaches private repos even if the SSH path is somehow broken.
  if git clone --branch "$REPO_REF" "$REPO_SSH" "$REPO_DIR" 2>/dev/null; then
    ok "cloned over SSH to $REPO_DIR"
  else
    warn "SSH clone failed; falling back to gh (HTTPS)."
    gh repo clone "$REPO_SLUG" "$REPO_DIR" -- --branch "$REPO_REF" \
      || die "Could not clone ${REPO_SLUG}."
    ok "cloned over HTTPS to $REPO_DIR"
  fi
}

step_setup() {
  log "Step 6/6 -- the rest of the setup"

  if [[ "$SKIP_SETUP" == true ]]; then
    ok "skipping (--skip-setup)"
    return 0
  fi

  local script="$REPO_DIR/linux/desktop-setup.sh"
  if [[ "$DRY_RUN" == true ]]; then
    printf '     $ %s --skip base,1password,gh,ssh\n' "$script"
    return 0
  fi

  [[ -x "$script" ]] || die "Expected $script to exist after cloning."

  # base, 1password, gh and ssh are already done above -- skipping them keeps
  # the output honest rather than printing four "already installed" lines.
  "$script" --skip base,1password,gh,ssh
}

# ---------------------------------------------------------------------------

main() {
  cat <<EOF
${C_BOLD}Linux desktop bootstrap${C_OFF}
${REPO_SLUG}

This installs 1Password first so you can reach your credentials, then signs
you in to GitHub, sets up an SSH key, clones the repo and runs the rest.

It will ask you to sign in twice along the way.
EOF

  [[ "$DRY_RUN" == true ]] && warn "Dry run -- nothing will be changed."

  fetch_setup_script
  step_packages
  step_1password
  step_gh
  step_ssh
  step_clone
  step_setup

  cat <<EOF

${C_GREEN}Bootstrap complete.${C_OFF}

  Repo:  ${REPO_DIR}
  Re-run any part later with:
      cd ${REPO_DIR}/linux && ./desktop-setup.sh --only <step>

EOF
}

main "$@"
