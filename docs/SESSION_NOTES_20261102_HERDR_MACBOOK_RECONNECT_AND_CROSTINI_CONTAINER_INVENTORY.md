# Session Notes: 2026-11-02 — Herdr MacBook Reconnection, Crostini Container Replication & Dotfile Analysis

## Overview

This session covered two primary workflows:
1. Resolving Herdr remote connection authentication to `ap-macbook` (`alan@100.87.229.122`).
2. Conducting an exhaustive audit of packages, third-party repositories, tools, dotfiles, and system services installed on ChromeOS Crostini (`penguin`) to design an exact replication blueprint for spinning up fresh Linux containers.

---

## 1. Herdr Remote Authentication: `ap-macbook`

### Context & Symptom
* `herdr machine status ap-macbook` reported:
  ```text
  status: auth required
  error: remote platform detection failed: alan@100.87.229.122: Permission denied (publickey,password,keyboard-interactive).
  ```
* Herdr was unable to manage panes or query remote agent sessions on the MacBook because OpenSSH key-based authentication was failing non-interactively.

### Root Cause Analysis
* Inspection of `/tmp/cb.log` and `~/.ssh/authorized_keys` revealed that the MacBook's public key (`alan@Mac`) had been added to Crostini's `~/.ssh/authorized_keys`, allowing inbound SSH from Mac to Crostini.
* However, Herdr on Crostini required outbound passwordless SSH into the MacBook (`alan@100.87.229.122`).
* When `ssh-copy-id -i ~/.ssh/id_ed25519.pub ap-macbook` was executed, the key was confirmed present on the MacBook.
* Subsequent SSH connection verification completed successfully:
  ```text
  debug1: Offering public key: /home/alanp2/.ssh/id_ed25519 ED25519 SHA256:F1zBw9ENsLqh3ElMcT31sH2gh5b4lB2dJj7FeOigCOU
  debug1: Server accepts key: /home/alanp2/.ssh/id_ed25519 ED25519 SHA256:F1zBw9ENsLqh3ElMcT31sH2gh5b4lB2dJj7FeOigCOU
  Authenticated to 100.87.229.122 using "publickey".
  ```
* Herdr status transitioned immediately from `auth required` to `reachable`:
  ```json
  [
    {
      "id": "92edac77d7831c591328160167ebacf4",
      "label": "ap-macbook",
      "status": "reachable",
      "error": null
    }
  ]
  ```
* Remote management via Herdr was verified with `herdr --machine ap-macbook agent list`, returning active agent sessions (`w1:p1` and `w1:p3` in `devices/ap-macbook-setup`).

---

## 2. Crostini Container Inventory & Replication Analysis

An exhaustive review of the current Crostini environment (`penguin` on Debian 13 "Trixie") was performed to determine whether a standard package list is sufficient to recreate the environment in a new container.

### Finding: APT Packages Alone Are Not Sufficient
Recreating Crostini requires 5 distinct layers:
1. **Third-Party APT Repositories & Keyrings**
2. **Debian APT Packages (Base & Utilities)**
3. **Stand-alone / User-level Binaries (`~/.local/bin`)**
4. **Tool-specific Package Managers (npm, uv/Python)**
5. **Dotfiles, SSH, and Configuration (`~/.config`, `~/.ssh`, etc.)**

---

### Layer-by-Layer Breakdown

#### A. Repositories (`/etc/apt/sources.list.d/`)
* **NodeSource Node.js 22.x LTS**:
  * Keyring: `/usr/share/keyrings/nodesource.gpg`
  * List: `/etc/apt/sources.list.d/nodesource.list`
* **Tailscale**:
  * Keyring: `/usr/share/keyrings/tailscale-archive-keyring.gpg`
  * List: `/etc/apt/sources.list.d/tailscale.list`
* **GitHub CLI (`gh`)**:
  * Keyring: `/etc/apt/keyrings/githubcli-archive-keyring.gpg`
  * List: `/etc/apt/sources.list.d/github-cli.list` (or `/etc/apt/sources.list.d/githubcli.list`)
* **Debian Trixie Base + ChromeOS Cros Packages**:
  * Default Crostini sources (`deb.debian.org/debian trixie`, `storage.googleapis.com/cros-packages-staging/157`).

#### B. Manually Installed APT Packages
* **Core tools**: `curl`, `wget`, `git`, `gnupg`, `jq`, `zip`, `unzip`, `less`, `procps`, `sed`, `grep`.
* **Editor & Shell**: `vim`, `neovim`, `mosh`, `bash-completion`.
* **Services & Remote Access**: `openssh-server`, `tailscale`, `tailscale-archive-keyring`.
* **Desktop / GUI / Wayland**: `wl-clipboard`, `remmina`, `remmina-plugin-rdp`, `syncthing`, `xvfb`.
* **Runtimes & SDKs**: `nodejs`, `python3`, `gh`.

#### C. User Binaries (`~/.local/bin/`)
* `herdr`: Terminal multiplexer and agent orchestration daemon.
* `agy`: Antigravity CLI binary.
* `uv` and `uvx`: Python package and tool runner (installed via Astral installer).
* `specify`: UV-installed tool (`~/.local/share/uv/tools/specify-cli/bin/specify`).
* `python3.14`: UV-managed standalone CPython toolchain.
* `wl-copy`: Wayland clipboard helper script.

#### D. Global NPM Packages (`/usr/lib/node_modules/`)
* `@tobilu/qmd@2.8.3`
* `corepack@0.36.0`
* `npm@10.9.9`

#### E. Dotfiles & Configuration Inventory
| Path | Description & Significance |
|---|---|
| `~/.ssh/` | Contains `id_ed25519` keypair, `authorized_keys` (Mac key), and `config` (host aliases for `ap-macbook` and `ap-elite`). |
| `~/.bashrc` | Contains `export PATH="/home/alanp2/.local/bin:$PATH"` and aliases. |
| `~/.gitconfig` | Configured user details and GitHub CLI git-credential helper (`gh auth git-credential`). |
| `~/.config/herdr/` | `config.toml`, socket definitions, session states, and snapshot history. |
| `~/.config/gh/` | GitHub CLI token configuration (`hosts.yml`, `config.yml`). |
| `~/.config/remmina/` | Remote desktop connection profiles. |
| `~/.gemini/` | Antigravity skills, configuration, and agent state (`~/.gemini/antigravity-cli`, `~/.gemini/config`). |
| `~/.clasprc.json` | Google Apps Script CLI auth tokens. |

---

## 3. Automated Container Provisioning Script

To reproduce this environment on any fresh Crostini or Debian container, save and execute the following bootstrap script:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "==> 1. Updating APT and installing prerequisites..."
sudo apt-get update
sudo apt-get install -y curl wget git gnupg jq mosh neovim vim zip unzip openssh-server wl-clipboard syncthing remmina remmina-plugin-rdp xvfb

echo "==> 2. Setting up third-party repositories..."
# GitHub CLI
sudo mkdir -p -m 755 /etc/apt/keyrings
wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list

# Node.js 22.x
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -

# Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

echo "==> 3. Installing repository packages..."
sudo apt-get update
sudo apt-get install -y gh nodejs tailscale tailscale-archive-keyring

echo "==> 4. Installing global NPM packages..."
sudo npm install -g @tobilu/qmd

echo "==> 5. Installing Astral uv and tools..."
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv tool install specify-cli --from specify-cli || true

echo "==> 6. Enabling services..."
sudo systemctl enable --now ssh
sudo systemctl disable tailscaled # Disabled on boot, started on demand

echo "==> 7. Creating standard directory structure..."
mkdir -p ~/.local/bin ~/.ssh ~/.config
chmod 700 ~/.ssh

echo "==> Complete! Don't forget to restore ~/.ssh keys, ~/.gitconfig, and ~/.gemini."
```
