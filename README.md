# mac-dev-playbook

Ansible playbook that takes a factory-fresh Mac to a working development
machine: Homebrew, the apps I use, language runtimes, an SSH key, my
[dotfiles](https://github.com/ekryski/dotfiles), and a pile of macOS defaults.

Tested on **macOS 26 (Tahoe)**, Apple Silicon, **ansible-core 2.21**.
Originally forked from [geerlingguy/mac-dev-playbook](https://github.com/geerlingguy/mac-dev-playbook).

> **On Linux?** There's a much smaller bash setup for Fedora and Ubuntu
> desktops in [`linux/`](linux/). On a machine with nothing on it:
>
> ```bash
> bash -c "$(curl -fsSL https://raw.githubusercontent.com/ekryski/mac-dev-playbook/main/linux/bootstrap.sh)"
> ```
>
> See [linux/README.md](linux/README.md).

## Quick start

On a machine with nothing installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ekryski/mac-dev-playbook/main/scripts/bootstrap.sh)"
```

That installs the Xcode Command Line Tools, Homebrew, git and Ansible, clones
this repo, and pulls the Galaxy collections. Then:

```bash
cd ~/Development/personal/mac-dev-playbook
cp config.example.yml config.yml   # optional overrides
ansible-playbook main.yml --ask-become-pass
```

`--ask-become-pass` is needed for the Xcode license, the software update policy
and the security settings. Everything else runs unprivileged.

For Waffuru work, run the [ops](https://github.com/waffuruai/ops) bootstrap
after this. The two don't overlap: this playbook owns
`~/.config/mise/config.toml` (your machine-wide defaults), and ops keeps its
own files beside it (`~/.config/mise/conf.d/waffuru.toml`, `~/waffuru/mise.toml`)
and installs Xcode with xcodes.

### If you already have Homebrew

```bash
brew install ansible
git clone https://github.com/ekryski/mac-dev-playbook.git
cd mac-dev-playbook
make install
```

## What it does

| Tag | Does |
|---|---|
| `xcode` | Verifies the Command Line Tools, accepts the Xcode license, runs first-launch |
| `homebrew` | Taps, formulae and casks |
| `mas` | Mac App Store apps (TestFlight, Pages, Numbers, Keynote) |
| `dotfiles` | oh-my-zsh, then clones the dotfiles repo and symlinks it into `$HOME` |
| `git` | Writes identity and the `gh` credential helper to `~/.gitconfig.local` |
| `claude` | Merges `claude_code_settings` into `~/.claude/settings.json`, keeping your other keys: by default, no Claude Code attribution on commits or PRs |
| `ssh` | Generates an ed25519 key, configures the agent + keychain, uploads to GitHub |
| `github` | Ensures `gh` + 1Password, pauses for sign-in, uploads the SSH key |
| `mise` | Your machine-wide node, ruby and go, as ranges kept at the newest patch |
| `python` | uv-managed interpreters and CLI tools |
| `rust` | rustup toolchain and components |
| `docker` | CLI plugins and the Colima VM |
| `services` | Optionally starts Postgres / Redis / MongoDB |
| `macos-defaults` | Keyboard, Finder, Dock, screenshot and trackpad preferences |
| `software-update` | Automatic checks, downloads, security responses, macOS and App Store updates |
| `security` | The settings Pantry checks: firewall and stealth mode, Gatekeeper, no guest or automatic login, sharing services off, AirDrop contacts only, network time, screen saver, then a report of what needs you (FileVault, SIP, admin account) |

Run one section on its own:

```bash
ansible-playbook main.yml --tags homebrew
```

Or skip one:

```bash
ansible-playbook main.yml --skip-tags mas,macos-defaults
```

See what would change without changing anything:

```bash
make dry-run
```

## Configuration

`default.config.yml` holds every variable and is the documentation. **Don't edit
it.** Copy `config.example.yml` to `config.yml` (gitignored) and override there —
it loads after the defaults, so anything it sets wins.

```yaml
# config.yml
git_user_email: "me@work.example"
homebrew_services_started:
  - postgresql@18
colima_cpus: 8
```

One gotcha: a list in `config.yml` **replaces** the default list, it doesn't
extend it. To add one cask, copy the whole `homebrew_casks` list over and append.

### Third-party taps

Homebrew 6 refuses to load formulae from a non-official tap until you explicitly
trust it — trusting a tap means letting its Ruby code run during install. The
playbook trusts everything in `homebrew_trusted_taps`, which is `mongodb/brew`
(MongoDB Inc.'s own tap) and nothing else. Add a tap there only if you actually
vouch for it.

## Installed software

### Development environment

| Area | Tooling |
|---|---|
| Package manager | Homebrew |
| Version manager | mise (node, ruby, go) |
| Python | uv — interpreters, venvs, and isolated CLI tools |
| Rust | rustup with clippy, rustfmt, rust-analyzer |
| Containers | docker CLI + compose + buildx, Colima (`vz` + Rosetta) |
| Databases | PostgreSQL 18, Redis, MongoDB Community, SQLite |
| Editors | Cursor, vim, Obsidian |
| Terminal | Ghostty + JetBrains Mono Nerd Font |
| Shell | zsh + oh-my-zsh, autosuggestions, syntax highlighting, fzf, zoxide |
| CLIs | Claude Code, gh, 1Password CLI, ansible, pandoc, ffmpeg, mactop, mole (`mo uninstall` removes an app and its leftovers), ripgrep, fd, bat, eza, jq, delta |

`nvm` is installed but not loaded — its shims conflict with mise's. The dotfiles
carry a commented block to switch back if a project demands it.

### Applications

Casks: Ghostty, Cursor, Obsidian, Brave, Google Chrome, Firefox, Slack, Discord,
Telegram, Claude, Claude Code, Linear, 1Password, Spotify, Screen Studio,
CapCut, Camo Studio, Transmission, Android Studio, DB Browser for SQLite,
Wireshark, balenaEtcher, Google Drive, DisplayLink Manager, Little Snitch,
NordVPN.

Mac App Store: TestFlight, Pages, Numbers, Keynote. Not Xcode: the App Store
updates its one Xcode.app in place, so install the versions you build with side
by side with `xcodes` (the ops bootstrap does).

The full list is in [default.config.yml](default.config.yml).

## Keeping it current

```bash
make update     # upgrade every formula, cask and App Store app, plus runtimes
```

Every run upgrades every formula and cask (`homebrew_upgrade_all`), and macOS
installs its own and App Store updates in between. Every run also upgrades
`ca-certificates` and `openssl@3`, and moves the mise
runtimes and uv Pythons to the newest patch in their configured range, removing
the ones they replace (`runtimes_upgrade: false` turns that off).

Re-running the whole playbook is safe and idempotent — that's the point.

## Still manual

Things Ansible genuinely can't do:

1. **Sign in to the App Store** before running with `--tags mas`.
2. **Little Snitch** needs approval in System Settings → Privacy & Security →
   Network Extensions, and a restart.
3. **Full Disk Access / Accessibility** grants for the terminal and Screen Studio;
   Screen Recording for DisplayLink Manager and Camo; Wireshark's capture helper
   (ChmodBPF) on its first launch.
4. **Sign in** to Slack, Linear, Discord, Spotify, Cursor, Claude, Telegram,
   Google Drive and NordVPN.
5. **FileVault**, if Setup Assistant didn't turn it on, and a **standard
   everyday account** with a separate admin one: the `security` tag reports
   both. Run `wpantry scan` afterwards to confirm the rest.
6. **`~/.zshrc.local`** — copy `.zshrc.local.example` from the dotfiles repo and
   fill in your tokens.
7. **1Password + `gh auth`** — the `ssh`/`github` tags pause with the commands
   to sign in to 1Password, then:
   `gh auth login -h github.com`,
   `gh auth refresh -h github.com -s admin:ssh_signing_key -s admin:public_key`,
   after which the playbook runs
   `gh ssh-key add --title "{Computer Name} ssh key" ~/.ssh/id_ed25519.pub`.
8. Some macOS defaults only apply after a logout or restart.

## Development

```bash
make lint       # ansible-lint (production profile) + yamllint
make check      # syntax check
make dry-run    # --check --diff
```

CI runs the linters, a syntax check and shellcheck on every push.

### Testing changes

There's no VM story any more — VirtualBox doesn't run on Apple Silicon, and the
old Vagrant setup in this repo targeted a hand-built El Capitan box. The
realistic options are:

- `make dry-run` to see what would change.
- Run a single tag against your own machine — everything is idempotent.
- A second user account on the same Mac, for a genuinely clean run.
