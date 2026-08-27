# Linux desktop setup

The Linux counterpart to the macOS Ansible playbook in the repo root —
deliberately much smaller, and a plain bash script rather than Ansible, because
Ansible isn't on a fresh Linux box either and this only installs nine things.

**Fedora and Ubuntu/Debian. Desktop only** — it installs GUI applications. A
headless server wants its own script; see [Server](#server) below.

## Quick start

```bash
git clone https://github.com/ekryski/mac-dev-playbook.git
cd mac-dev-playbook/linux
./desktop-setup.sh
```

Look before you leap:

```bash
./desktop-setup.sh --dry-run
```

## What it installs

| Step | Installs | Source |
|---|---|---|
| `base` | curl, wget, git, gnupg, build tools | distro repos |
| `ssh` | openssh client, an ed25519 key, agent + known_hosts config | distro repos |
| `gpg` | gnupg + pinentry, gpg-agent cache tuning | distro repos |
| `gh` | GitHub CLI | signed repo, `cli.github.com` |
| `brave` | Brave browser | signed repo, `brave.com` |
| `1password` | 1Password desktop app + `op` CLI (see [Architecture](#architecture)) | signed repo, `1password.com` |
| `nordvpn` | NordVPN CLI + GUI | signed repo, `repo.nordvpn.com` |
| `mise` | mise, then Node.js LTS | `mise.run` install script |
| `uv` | uv, then Python 3.14 | `astral.sh` install script |

Node and Python are handled by mise and uv rather than distro packages, so the
versions match what the macOS playbook installs and don't drift with the OS.

## Architecture

Written for **x86_64**, which is what a normal Linux desktop is. It runs on
arm64 too, with one gap:

**1Password's desktop app is x86_64-only on Linux.** Their arm64 package repo
contains `1password-cli` and nothing else. On arm64 the script notices, installs
just the CLI, and says so — rather than asking for a package that doesn't exist
and failing the whole transaction. Use the 1Password browser extension in Brave
on those machines.

Everything else — Brave, gh, NordVPN, mise, uv — has arm64 builds.

## Running part of it

Steps are named. Run some:

```bash
./desktop-setup.sh --only gh,mise,uv
```

Or all but some:

```bash
./desktop-setup.sh --skip nordvpn,brave
```

Unknown step names are rejected before anything is installed, so a typo can't
quietly no-op.

## Re-running

Safe. Every step checks before it acts: packages already present are skipped, an
existing SSH key is **never** regenerated, and the SSH/gpg-agent config blocks
are marked and only appended once.

## Trust surface

Worth knowing what you're trusting, since most of this comes from outside the
distro:

- **gh, Brave, 1Password, NordVPN** install from the vendor's own signed
  package repository. Packages are GPG-verified by `apt`/`dnf` on every update.
- **Signing keys are fingerprint-checked after import**, and a mismatch aborts
  before the repository is added:
  1Password `3FEF9748469ADBE15DA7CA80AC2D62742012EA22`,
  NordVPN `BC5480EFEC5C081CE5BCFBE26B219E535C964CA1`.
  On Debian/Ubuntu the script also installs 1Password's `debsig` policy, so the
  `.deb` itself is verified on top of the repo signature.
- **NordVPN's repo is configured directly** rather than via either of the two
  routes they document, both of which have problems. Their `curl … | sh`
  one-liner executes a script fetched over the wire. Their `nordvpn-release`
  package is worse than it looks: the RPM carries no digest, so RPM 4.20+
  (Fedora 41+) refuses to install it outright, and the `.deb` drops their key
  into `/etc/apt/trusted.gpg.d/`, where it is trusted for *every* repo on the
  system rather than just NordVPN's. The script writes a `signed-by=`-scoped
  repo instead, using the key published at `repo.nordvpn.com/gpg` — verified to
  be byte-identical to the one inside their release package.
- **mise and uv** are installed with their vendors' official `curl | sh`
  installers. Neither is packaged for Ubuntu, and this is the documented path.
  If that trade-off bothers you, install them from
  [mise releases](https://github.com/jdx/mise/releases) and
  [uv releases](https://github.com/astral-sh/uv/releases) by hand and the script
  will detect them and skip ahead.

## After it finishes

The script prints these, but in short:

1. Put `~/.local/bin` on `PATH` and hook up mise:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   eval "$(mise activate bash)"   # or zsh
   ```
2. `gh auth login`, then `gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)"`
3. Import your GPG signing key from the machine that has it — the script
   installs gnupg but deliberately does **not** generate a key, since you want
   the same identity across machines:
   ```bash
   gpg --import private.key
   git config --global user.signingkey <KEY_ID>
   ```
4. `nordvpn login`, and log out/in once so the `nordvpn` group takes effect.
5. Sign in to 1Password.

## Dotfiles

The script doesn't touch dotfiles. The
[dotfiles repo](https://github.com/ekryski/dotfiles) is macOS-shaped right now —
`.zprofile` assumes Homebrew paths. Clone it and link by hand if you want it, or
wait until it grows a Linux branch in its `.zprofile`.

## Server

Not written yet. When it is, it belongs beside this as `server-setup.sh`,
sharing the same step structure minus Brave, the 1Password desktop app and the
NordVPN GUI. In the meantime `--skip brave,1password,nordvpn` gets most of the
way there on a headless box.

## Testing

The script is shellcheck-clean and is exercised on real `ubuntu:24.04` and
`fedora:latest` containers. To re-run that yourself:

```bash
docker run --rm -v "$PWD:/mnt:ro" ubuntu:24.04 bash -c \
  'apt-get update -qq && apt-get install -y -qq sudo curl >/dev/null
   useradd -m -s /bin/bash tester
   echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
   cp /mnt/desktop-setup.sh /home/tester/ && chown tester /home/tester/desktop-setup.sh
   sudo -u tester -i ./desktop-setup.sh --dry-run'
```

Containers have no display server and no systemd, so GUI apps install but can't
launch, and NordVPN's daemon won't start there. That's expected.
