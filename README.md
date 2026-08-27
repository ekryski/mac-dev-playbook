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

`--ask-become-pass` is needed for the Xcode license acceptance. Everything else
runs unprivileged.

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
| `mas` | Mac App Store apps (Xcode, TestFlight, Pages, Numbers, Keynote) |
| `dotfiles` | Clones the dotfiles repo and symlinks it into `$HOME` |
| `git` | Writes identity and the `gh` credential helper to `~/.gitconfig.local` |
| `ssh` | Generates an ed25519 key, configures the agent + keychain, uploads to GitHub |
| `mise` | node, ruby and go |
| `python` | uv-managed interpreters and CLI tools |
| `rust` | rustup toolchain and components |
| `docker` | CLI plugins and the Colima VM |
| `services` | Optionally starts Postgres / Redis / MongoDB |
| `macos-defaults` | Keyboard, Finder, Dock, screenshot and trackpad preferences |

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
| Editors | Cursor, vim |
| Terminal | Ghostty + JetBrains Mono Nerd Font |
| Shell | zsh + oh-my-zsh, autosuggestions, syntax highlighting, fzf, zoxide |
| CLIs | gh, 1Password CLI, ansible, pandoc, ffmpeg, mactop, mole, ripgrep, fd, bat, eza, jq, delta |

`nvm` is installed but not loaded — its shims conflict with mise's. The dotfiles
carry a commented block to switch back if a project demands it.

### Applications

Casks: Ghostty, Cursor, Brave, Google Chrome, Slack, Discord, Claude, Linear,
1Password, Spotify, Screen Studio, Little Snitch.

Mac App Store: Xcode, TestFlight, Pages, Numbers, Keynote.

The full list is in [default.config.yml](default.config.yml).

## Keeping it current

```bash
make update     # upgrade every formula, cask and App Store app
```

Re-running the whole playbook is safe and idempotent — that's the point.

## Still manual

Things Ansible genuinely can't do:

1. **Sign in to the App Store** before running with `--tags mas`.
2. **Little Snitch** needs approval in System Settings → Privacy & Security →
   Network Extensions, and a restart.
3. **Full Disk Access / Accessibility** grants for the terminal and Screen Studio.
4. **Sign in** to 1Password, Slack, Linear, Discord, Spotify, Cursor and Claude.
5. **`~/.zshrc.local`** — copy `.zshrc.local.example` from the dotfiles repo and
   fill in your tokens.
6. **`gh auth login`** — run it before `--tags ssh` if you want the SSH key
   uploaded to GitHub automatically.
7. Some macOS defaults only apply after a logout or restart.

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
