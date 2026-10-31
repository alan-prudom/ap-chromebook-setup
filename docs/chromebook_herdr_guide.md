# Herdr Comprehensive User Manual (ChromeOS Crostini & Fleet Guide)

**Version Target:** Herdr `0.9.5+` (Stable Channel)  
**Primary Client Environment:** ChromeOS Crostini (`penguin` Debian container)  
**Fleet Nodes:** `Local` (Chromebook), `ap-elite`, `ap-macbook`, `AP-HP-G5`, `popos`, `thinkpad`, `aws-caddy`  
**Canonical Upstream Docs:** [https://herdr.dev/tui/docs/](https://herdr.dev/tui/docs/)

---

## Table of Contents
1. [What Herdr Is & Core Concept Model](#1-what-herdr-is--core-concept-model)
2. [Installation & Crostini Environment Setup](#2-installation--crostini-environment-setup)
3. [Mouse-First Controls & Copy/Paste in Crostini](#3-mouse-first-controls--copypaste-in-crostini)
4. [Keyboard Reference & Navigation Modes](#4-keyboard-reference--navigation-modes)
5. [Session Persistence, Snapshots & Crostini Sleep](#5-session-persistence-snapshots--crostini-sleep)
6. [Multi-Machine & Remote Fleet Workflows (`herdr machine`)](#6-multi-machine--remote-fleet-workflows-herdr-machine)
7. [AI Coding Agent Integrations & Agent Orchestration](#7-ai-coding-agent-integrations--agent-orchestration)
8. [Git Worktree Workflows](#8-git-worktree-workflows)
9. [Configuration & Customization (`config.toml`)](#9-configuration--customization-configtoml)
10. [CLI Reference & Troubleshooting Recipes](#10-cli-reference--troubleshooting-recipes)

---

## 1. What Herdr Is & Core Concept Model

Herdr is a **mouse-first, agent-aware terminal workspace manager** (multiplexer). Like `tmux`, a persistent background server owns your real terminal processes (PTYs), and terminal clients attach to render them. Unlike `tmux`, the entire UI is clickable and natively understands AI coding agents running inside panes.

### 1.1 Hierarchy of Concepts (Top to Bottom)

```
Session (default background server namespace)
 └── Machine (Local Crostini server or saved remote SSH machine, e.g. ap-elite)
      └── Workspace (w1, w2... — one per project/repo or task)
           └── Tab (w1:t1, w1:t2... — layout views inside a workspace: agents, logs, server)
                └── Pane (w1:p1, w1:p2... — real splittable terminal shell)
                     └── Agent (detected AI coding agent inside a pane: agy, claude, codex...)
```

| Concept | Public ID Format | Description |
| :--- | :--- | :--- |
| **Session** | `default` (or named) | A persistent background server namespace (`~/.config/herdr/herdr.sock`). Running `herdr` attaches to `default`. Named sessions (`herdr --session work`) are isolated servers; most workflows only need `default`. |
| **Machine** | `Local` or `<label>` | A local or remote Herdr server shown in the left Sidebar (`Spaces`). Each machine keeps its own server, sessions, and running processes independently. |
| **Workspace** | `w1`, `w2` | The project-level container (typically one per Git repository or investigation). Owns tabs and panes. The sidebar rolls up agent states per workspace. |
| **Tab** | `w1:t1`, `w1:t2` | A layout inside a workspace for separating views (e.g., coding agents in Tab 1, dev servers/logs in Tab 2). |
| **Pane** | `w1:p1`, `w1:p2` | A real terminal process that can be split horizontally (`right`) or vertically (`down`). Survives client detach. Closed pane/tab IDs are never reused. |
| **Agent** | `name` or `w1:p1` | A recognized coding agent running inside a pane. Reports live states in the sidebar: **`working`**, **`blocked`** (waiting for approval/input), **`done`** (finished turn, unseen), **`idle`**, or **`unknown`**. |

### 1.2 Input Modes
- **Terminal Mode (Default):** All keypresses go directly to the focused terminal pane.
- **Prefix Mode (`Ctrl+b`, release, then action key):** Sends a single command to Herdr (e.g., `Ctrl+b` then `v` splits right), then immediately returns to Terminal Mode.
- **Navigate / Picker / Resize / Copy Modes:** Modal surfaces for jumping across workspaces (`Ctrl+b w`), searching all agents/panes (`Ctrl+b g`), resizing splits (`Ctrl+b r`), or keyboard scrolling/selection (`Ctrl+b [`).

---

## 2. Installation & Crostini Environment Setup

### 2.1 Install Herdr Binary
Inside your ChromeOS Linux Terminal:
```bash
curl -fsSL https://herdr.dev/install.sh | sh
herdr --version
```
- Installed binary path: `~/.local/bin/herdr`
- Update at any time: `herdr update`

### 2.2 Install Agent Lifecycle Integration & Global Skill
1. **Install Antigravity (`agy`) integration** (tracks live agent states and enables native conversation restore across restarts):
   ```bash
   herdr integration install antigravity-cli
   herdr integration status
   ```
   *(If you install other agents like `claude`, `codex`, `copilot`, or `opencode`, run `herdr integration install <name>` for each).*
2. **Install the Official Herdr Agent Skill Globally** (teaches Antigravity how to split panes, run commands in background panes, and coordinate sibling agents when `HERDR_ENV=1`):
   ```bash
   mkdir -p ~/.gemini/config/skills/herdr
   curl -fsSL https://raw.githubusercontent.com/herdrdev/herdr/master/skills/herdr/SKILL.md \
     -o ~/.gemini/config/skills/herdr/SKILL.md
   ```

---

## 3. Mouse-First Controls & Copy/Paste in Crostini

You do not need to memorize any keybindings to use Herdr—every action is available with the mouse:

- **Focus a Pane, Tab, or Workspace:** Left-click any pane, tab header, or sidebar item.
- **Split, Close, or Zoom Panes:** **Right-click** inside any pane to open the context menu (`Split right`, `Split down`, `Zoom pane`, `Close pane`, etc.).
- **Resize Split Panes:** Click and drag the divider border between any two panes.
- **Create / Manage Tabs & Workspaces:** Click the `+` button in the tab bar or sidebar, or right-click existing tabs/workspaces to rename or close them.
- **Collapse / Expand Sidebar Sections:** Click the arrow next to any machine (`Local`, `ap-elite`) in the sidebar to expand or collapse its workspace list without switching away from your active pane.

### 3.1 How Copying to the ChromeOS Clipboard Works
Herdr has `copy_on_select = true` enabled by default:
- **Single-Pane Multi-Line Copy (Recommended):** Simply **left-click and drag** across one or more lines inside a pane and release the mouse button. Because Herdr owns the pane geometry, **selection stays strictly inside that pane** and will never grab text from the sidebar or adjacent split panes.
- **Outer Terminal Override (`Shift` + Drag):** Holding `Shift` while dragging bypasses Herdr and uses the ChromeOS Terminal's native selection (which spans the full width of the window across vertical splits).

#### Why Crostini Needs the `~/.local/bin/wl-copy` Bridge
Crostini sets `WAYLAND_DISPLAY=wayland-0`, causing Herdr to invoke `wl-copy`. However, ChromeOS's `sommelier` Wayland compositor blocks headless CLI processes (`wl-copy`) from claiming the clipboard because they don't own a GUI Wayland window, whereas XWayland (`xclip`) and `OSC 52` escape sequences bridge directly to the ChromeOS system clipboard.

Ensure `xclip` and the `~/.local/bin/wl-copy` wrapper are installed:
```bash
sudo apt update && sudo apt install -y xclip

cat << 'EOF' > ~/.local/bin/wl-copy
#!/usr/bin/env bash
input="$(cat)"
if [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
    printf '%s' "$input" | xclip -selection clipboard -in 2>/dev/null || true
fi
if [ -w /dev/tty ]; then
    b64="$(printf '%s' "$input" | base64 | tr -d '\r\n')"
    printf '\033]52;c;%s\a' "$b64" > /dev/tty 2>/dev/null || true
fi
exit 0
EOF
chmod +x ~/.local/bin/wl-copy
```

---

## 4. Keyboard Reference & Navigation Modes

In Herdr, **`prefix`** means: press **`Ctrl+b`**, release both keys, then press the action key.

> **Live Cheat Sheet:** Press **`Ctrl+b` then `?`** at any time inside Herdr to open the searchable live keybinding overlay (press `/` to filter, `Esc` to close).

### 4.1 The Top 5 Shortcuts to Learn First

| Action | Shortcut | What It Does |
| :--- | :--- | :--- |
| **Split Right / Down** | `Ctrl+b` `v` / `Ctrl+b` `-` | Splits the focused pane horizontally (right) or vertically (down). |
| **New Tab** | `Ctrl+b` `c` | Creates a new tab in the current workspace. |
| **Move Between Panes** | `Ctrl+b` `h` / `j` / `k` / `l` | Moves focus left (`h`), down (`j`), up (`k`), or right (`l`). |
| **Workspace Switcher** | `Ctrl+b` `w` | Highlights the sidebar workspace list (Up/Down to select across machines, `Enter` to activate). |
| **Detach Session** | `Ctrl+b` `q` | Detaches the client cleanly and returns to bash; all panes keep running in the background. |

### 4.2 Complete Default Keymap by Category

#### Panes
| Action | Shortcut |
| :--- | :--- |
| Split pane right | `Ctrl+b` `v` |
| Split pane down | `Ctrl+b` `-` |
| Focus pane (Left / Down / Up / Right) | `Ctrl+b` `h` / `j` / `k` / `l` |
| Swap pane (Left / Down / Up / Right) | `Ctrl+b` `Shift+H` / `J` / `K` / `L` |
| Zoom / Unzoom focused pane (fullscreen toggle) | `Ctrl+b` `z` |
| Close focused pane | `Ctrl+b` `x` |
| Enter Resize mode (use arrows/`hjkl` to resize, `Esc` to exit) | `Ctrl+b` `r` |
| Enter Copy / Scrollback mode (`Esc` to exit) | `Ctrl+b` `[` |

#### Tabs
| Action | Shortcut |
| :--- | :--- |
| Create new tab | `Ctrl+b` `c` |
| Next / Previous tab | `Ctrl+b` `n` / `Ctrl+b` `p` |
| Jump directly to tab 1–9 | `Ctrl+b` `1` .. `9` |
| Rename current tab | `Ctrl+b` `Shift+T` |
| Close current tab | `Ctrl+b` `Shift+X` |

#### Workspaces, Pickers & Session
| Action | Shortcut |
| :--- | :--- |
| **Goto Picker** (search all agents, panes, branches, workspaces) | `Ctrl+b` `g` (press `/` to filter, `Enter` to jump) |
| **Workspace Picker** (navigate sidebar across Local & remote machines) | `Ctrl+b` `w` |
| Jump to latest notification / blocked agent target | `Ctrl+b` `o` |
| Toggle left Sidebar (expanded ↔ compact/hidden) | `Ctrl+b` `b` |
| Create new workspace | `Ctrl+b` `Shift+N` |
| Create new Git worktree workspace | `Ctrl+b` `Shift+G` |
| Rename current workspace | `Ctrl+b` `Shift+W` |
| Close current workspace | `Ctrl+b` `Shift+D` |
| Open Settings dialog | `Ctrl+b` `s` |
| Reload `config.toml` live | `Ctrl+b` `Shift+R` |
| Detach from Herdr (leave server & panes running) | `Ctrl+b` `q` |

---

## 5. Session Persistence, Snapshots & Crostini Sleep

Herdr uses a multi-layered persistence architecture stored in `~/.config/herdr/`:

1. **Live Background Server (`herdr.sock`):**
   - Detaching (`Ctrl+b` `q`) or closing a single terminal tab leaves the `herdr server` daemon running in the background. Run `herdr` to reattach immediately with zero interruption.
   - *Note:* Never run `herdr` from *inside* an existing Herdr pane (`HERDR_ENV=1`)—Herdr blocks nested sessions by design.
2. **Crostini Sleep / VM Suspend Caveat:**
   - Because ChromeOS suspends the Crostini VM (`termina`) when all Linux windows are closed for an extended period or when the Chromebook enters sleep, **long-running local agent jobs will pause if the Chromebook sleeps**, and in-flight TCP connections (such as active LLM streaming calls) may time out upon wake.
   - **To keep local Crostini jobs running unattended:**
     - Set *ChromeOS Settings → System Preferences → Power → When idle* to **Keep display on** (or **Turn off display** instead of **Sleep**).
     - Or enable the ChromeOS **Keep Awake** shelf toggle/extension.
     - For overnight/lid-closed jobs, run the agent on a remote fleet machine (`ap-elite`, `aws-caddy`, `popos`) via `herdr machine` (see Section 6).
3. **Snapshot & Native Agent Session Restore (`session.json`):**
   - Every layout change and agent session ID is automatically saved to `~/.config/herdr/session.json` and backed up in `~/.config/herdr/session-snapshots/`.
   - If Crostini shuts down or the Chromebook reboots, running `herdr` automatically reconstructs your workspaces, tabs, split ratios, working directories, and **resumes your active Antigravity (`agy`) conversation** in place (`[session] resume_agents_on_restore = true`).
4. **Full Shutdown (When You Actually Want to Stop Everything):**
   ```bash
   herdr server stop
   ```

---

## 6. Multi-Machine & Remote Fleet Workflows (`herdr machine`)

Herdr allows you to manage your local Chromebook workspaces and remote fleet servers (`ap-elite`, `AP-HP-G5`, `popos`, `aws-caddy`) **in one unified window**, or connect per-pane via SSH.

### 6.1 Choosing the Right Remote Pattern

| Goal | How to Do It | What Happens |
| :--- | :--- | :--- |
| **1. Full Remote Workspaces in Sidebar** | Run `herdr machine add <user@host> --label <name>`, then **click `<name>` in the left Sidebar**. | Your local Herdr UI switches between `Local` workspaces and the remote machine's Herdr server. Remote agents appear in your sidebar and keep running on the remote server even when your Chromebook is asleep/offline. |
| **2. Side-by-Side Remote Shell in One Local Pane** | Split a local pane (`Ctrl+b v` or `-`) and run **`ssh <user@host>`** inside that pane. | Gives you an interactive shell on `ap-elite` right next to your local Chromebook panes inside the same `Local` tab. *(Do not run `herdr` inside that small SSH pane, or you'll nest two TUIs).* |
| **3. Direct Thin-Client Attach Only** | From a non-Herdr bash shell, run **`herdr --remote <user@host>`**. | Attaches your terminal directly to the remote machine's Herdr server without using a local Herdr server. |

### 6.2 Registering Your Fleet Machines
Run these from an interactive terminal pane so SSH can authenticate:
```bash
# Home Server (ap-elite) — Already added!
herdr machine add alan@100.110.200.56 --label ap-elite

# MacBook Air (ap-macbook / alans-macbook-air-9.manee-dab.ts.net)
herdr machine add alan@100.87.229.122 --label ap-macbook

# Pop!_OS Desktop
herdr machine add alan@100.127.14.83 --label popos

# AWS Cloud Gateway (aws-caddy)
herdr machine add ec2-user@100.88.201.57 --label aws-caddy

# HP ZBook G5 Workstation
herdr machine add alanp@100.127.153.93 --label ap-hp-g5
```

### 6.3 Switching Between `Local` and `ap-elite`
- **With the Mouse:** Look at the left Sidebar under **Spaces**. Click **`ap-elite`** (or click the arrow next to `ap-elite` to expand its workspaces and click a workspace). Click **`Local`** to switch back to your Chromebook panes.
- **With the Keyboard:** Press **`Ctrl+b` `w`**, use the `Up`/`Down` arrow keys to highlight a workspace under `ap-elite` or `Local`, and press **`Enter`**.

### 6.4 Reconnecting After Sleep or SSH Idle Timeout
Herdr shares an OpenSSH connection (`ControlPersist 600` = 10 minutes idle timeout) when `remote.manage_ssh_config = true`.
- If a remote machine in the sidebar shows **`! auth`** or **`disconnected`** (for example, if SSH requires a password or key passphrase rather than an unlocked passwordless key in `ssh-agent`), run this in any terminal pane to re-authenticate:
  ```bash
  herdr machine reconnect ap-elite
  ```
- **Pro Tip for Seamless Auto-Reconnect:** Add your SSH key to Crostini's `ssh-agent` (`ssh-add ~/.ssh/id_rsa` or `id_ed25519`) and copy your public key to `ap-elite` (`ssh-copy-id alan@100.110.200.56`). With key-based auth, Herdr reconnects to `ap-elite` automatically in the background without ever needing `herdr machine reconnect`!

### 6.5 Managing Saved Machine Profiles
```bash
herdr machine list                  # List saved machines and their profile IDs
herdr machine status                # Non-interactive reachability check
herdr machine reconnect ap-elite    # Interactive SSH re-authentication
herdr machine disable <profile-id>  # Temporarily stop connecting to a machine
herdr machine enable <profile-id>   # Re-enable a disabled machine
herdr machine remove <profile-id>   # Remove profile from sidebar (leaves remote server running)
```

### 6.6 Keeping macOS (`ap-macbook`) Sessions Awake When Screen Is Locked
When locking the screen on macOS, the system and Wi-Fi/Tailscale interfaces aggressively enter deep sleep shortly after the display turns off, freezing SSH and Herdr sessions.

1. **Prevent Sleep via `pmset` (Run on `ap-macbook`):**
   ```bash
   # Prevent system sleep while on AC power (allows display to still turn off/lock)
   sudo pmset -c sleep 0

   # Prevent idle sleep while any remote SSH/terminal user is logged in
   sudo pmset -a ttyskeepawake 1

   # Enable Wake for network access
   sudo pmset -a womp 1
   ```
   *(To also prevent sleep on battery when locked, use `sudo pmset -a sleep 0` or run `caffeinate -isd &` inside your macOS session).*

2. **SSH KeepAlives on Chromebook (`~/.ssh/config`):**
   Configured in `~/.ssh/config` so the local SSH client detects drops quickly and keeps Tailscale connections warm:
   ```ssh-config
   Host ap-macbook 100.87.229.122 alans-macbook-air-9.manee-dab.ts.net
       HostName 100.87.229.122
       User alan
       ServerAliveInterval 15
       ServerAliveCountMax 3
       TCPKeepAlive yes

   Host ap-elite 100.110.200.56
       HostName 100.110.200.56
       User alan
       ServerAliveInterval 15
       ServerAliveCountMax 3
       TCPKeepAlive yes

   Host *
       ServerAliveInterval 15
       ServerAliveCountMax 3
       TCPKeepAlive yes
   ```

---

## 7. AI Coding Agent Integrations & Agent Orchestration

### 7.1 Understanding Sidebar Agent States
Herdr monitors every pane for supported coding agents (`agy`, `claude`, `codex`, `copilot`, `opencode`, `cursor`, `gemini`, etc.) and displays their status badge in the **Agents** and **Spaces** sidebar sections:

- **`working`** — The agent is actively executing tools, running commands, or generating a response.
- **`blocked`** — The agent is waiting on an approval prompt or multiple-choice question from you (highest attention priority; jump straight to it with `Ctrl+b o`).
- **`done`** — The agent finished its turn while you were looking at another pane/tab/workspace and you haven't viewed it yet. Focusing the pane clears `done` to `idle`.
- **`idle`** — The agent is at its input prompt waiting for your next instruction.
- **`unknown`** — An agent process is present, or a normal shell is running, and Herdr cannot classify a specific agent state.

### 7.2 Asking Antigravity to Control Herdr for You
Because `~/.gemini/config/skills/herdr/SKILL.md` is installed, whenever you are talking to Antigravity inside a Herdr pane, you can ask it in plain English to:
1. **"Split a pane to the right in Herdr and run `htop` (or a test suite) without stealing focus."**
2. **"Read the output from pane `w1:p2` (or the lower-right pane) and summarize the error."**
3. **"Split a new pane in Herdr, start an agent named `reviewer`, and ask it to review the current git diff."**
4. **"Check what agents and workspaces are running on `ap-elite` via Herdr."**

### 7.3 Manual CLI Agent Orchestration Examples
You (or scripts) can also run these commands directly in any pane:
```bash
# List all detected agents in the current session
herdr agent list

# Explain why Herdr classified a pane's agent state a certain way
herdr agent explain w1:p1 --json

# Split a sibling pane without stealing focus
herdr pane split --current --direction right --cwd "$PWD" --no-focus

# Run a command in pane w1:p2 and read the last 50 unwrapped lines
herdr pane run w1:p2 "git status -sb"
herdr pane read w1:p2 --source recent-unwrapped --lines 50

# Target a saved remote machine (e.g. ap-elite) from your local pane
herdr --machine ap-elite workspace list
herdr --machine ap-elite agent list
```

---

## 8. Git Worktree Workflows

When working on multiple features or branches in the same repository simultaneously (for example, running two coding agents in parallel without them stepping on each other's working tree):

- **Keyboard Shortcut:** Press **`Ctrl+b` `Shift+G`** (`new_worktree`) from inside a Git repository workspace.
- **CLI Commands:**
  ```bash
  herdr worktree list
  herdr worktree create --branch feat/new-experiment
  herdr worktree open <path>
  herdr worktree remove <path>
  ```
- Herdr creates a linked workspace grouped cleanly under the parent repository workspace in your sidebar, storing worktrees in `~/.herdr/worktrees` by default.

---

## 9. Configuration & Customization (`config.toml`)

Herdr's configuration file lives at **`~/.config/herdr/config.toml`**.
- View all available settings and defaults: `herdr --default-config`
- Apply changes live without restarting panes: `herdr server reload-config` (or press **`Ctrl+b` `Shift+R`**).

### 9.1 Recommended `config.toml` Examples

Your current `~/.config/herdr/config.toml` is:
```toml
onboarding = false

[theme]
name = "terminal"
auto_switch = false
```

Here are useful optional customizations you can add to `~/.config/herdr/config.toml`:

```toml
onboarding = false

[theme]
# Built-in themes: catppuccin, terminal, tokyo-night, dracula, nord,
#                  gruvbox, one-dark, solarized, kanagawa, rose-pine, vesper
name = "terminal"
auto_switch = false

[ui]
# Show detected agent labels in split pane borders
show_agent_labels_on_pane_borders = true

# Copy selected text automatically on mouse release (default: true)
copy_on_select = true

# Sort agents in the top sidebar panel by attention priority ("priority") or workspace ("spaces")
agent_panel_sort = "spaces"

[ui.toast]
# Show in-app toast notifications when a background agent finishes or is blocked
# Options: "off", "herdr", "terminal", "system"
delivery = "herdr"
delay_seconds = 1

[session]
# Automatically resume supported AI-agent conversations after a server restart
resume_agents_on_restore = true

[experimental]
# Save and replay recent pane screen history across full server restarts/reboots
pane_history = true
```

---

## 10. CLI Reference & Troubleshooting Recipes

### 10.1 Essential CLI Commands
```bash
# Session & Server Status
herdr status                        # Summary of client, server, and protocol compatibility
herdr server reload-config          # Reload ~/.config/herdr/config.toml live
herdr server stop                   # Stop the local Herdr background server and all panes
herdr update                        # Update Herdr binary to latest release

# Layout Discovery (inside HERDR_ENV=1)
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr pane layout --pane "$HERDR_PANE_ID"
```

### 10.2 Troubleshooting Quick Recipes

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| **"Cannot launch herdr inside an existing herdr pane"** | You ran `herdr` inside a pane where `HERDR_ENV=1` is already active. | You are already inside Herdr! Use the sidebar, tabs, or `Ctrl+b` shortcuts instead. |
| **Mouse drag-select doesn't copy to ChromeOS clipboard** | Crostini's `WAYLAND_DISPLAY` triggers `wl-copy`, which `sommelier` blocks for CLI apps. | Ensure `xclip` and the `~/.local/bin/wl-copy` wrapper script from [Section 3.1](#31-how-copying-to-the-chromeos-clipboard-works) are installed. |
| **`Shift` + drag-select copies text from the left pane/sidebar too** | Holding `Shift` bypasses Herdr and uses the outer terminal's full-width selection. | Release `Shift` and use a normal left-click drag inside the pane so Herdr clips selection to that single pane's borders. |
| **Remote machine (`ap-elite`) shows `! auth` or `disconnected` in sidebar** | SSH connection timed out or needs interactive password/key authentication. | Run `herdr machine reconnect ap-elite` in any pane (or set up passwordless SSH keys with `ssh-copy-id alan@100.110.200.56`). |
| **A keyboard shortcut (chord) does nothing** | ChromeOS or the ChromeOS Terminal app intercepted the shortcut before Herdr saw it. | Use prefix mode (`Ctrl+b` then key), check `Ctrl+b ?`, or rebind the action under `[keys]` in `~/.config/herdr/config.toml`. |
| **Need to inspect server or client logs** | Diagnosing startup or SSH bridge issues. | Check `~/.config/herdr/herdr-server.log` and `~/.config/herdr/herdr-client.log`. |
| **macOS (`ap-macbook`) SSH / Herdr session freezes on lock screen** | macOS puts system/Wi-Fi/Tailscale to sleep when the display locks. | Run `sudo pmset -c sleep 0`, `sudo pmset -a ttyskeepawake 1`, and `sudo pmset -a womp 1` on the Mac (or `caffeinate -isd &`), and ensure `ServerAliveInterval 15` is set in `~/.ssh/config` (see [Section 6.6](#66-keeping-macos-ap-macbook-sessions-awake-when-screen-is-locked)). |
