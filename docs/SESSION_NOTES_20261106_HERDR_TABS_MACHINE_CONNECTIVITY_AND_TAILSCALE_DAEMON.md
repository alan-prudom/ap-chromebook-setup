# Engineering & Session Notes: Herdr Tab Management, Fleet Machine Connectivity, and Tailscale Daemon Automation

**Date:** 2026-11-06  
**Repository:** `alan-prudom/ap-devices-and-pcs`  
**Related Components:** Herdr Multi-Agent Multiplexer, Tailscale Mesh Network (`ap-elite`, `ap-macbook`, `rp4-2gb`), Local System Automation

---

## 1. Executive Summary

This session covered three primary operational and infrastructure workflows:
1. **Herdr Workspace & Tab Management**:
   - Examined Herdr tab navigation and renaming commands (`herdr tab rename`).
   - Identified active workspace (`w1`) topology and renamed tab `w1:t1` to `"Assembly A26-2"`.
2. **Homelab & Remote Machine Connectivity Diagnostics (`ap-elite` vs `ap-macbook` vs `rp4-2gb`)**:
   - Investigated why `ap-elite` and `ap-macbook` were failing to auto-connect or reporting errors compared to `rp4-2gb`.
   - Identified root causes on `ap-elite`: non-login SSH `PATH` missing `/home/alan/.local/bin/herdr`, raw Tailscale IP timeout vs MagicDNS, and Tailscale SSH approval requirements.
   - Verified that `/usr/local/bin/herdr -> /home/alan/.local/bin/herdr` symlink resolved remote platform detection, transitioning `ap-elite` to `reachable` with live pane queries.
   - Identified that `ap-macbook`'s connection drops are tied to host sleep / lid close events.
3. **Tailscale Daemon Startup Script**:
   - Developed a robust shell script [`start-tailscale.sh`](../start-tailscale.sh) to ensure `tailscaled` is running (handling both `systemd` environments and standalone/container fallback daemon launches) and bringing the Tailscale mesh online with SSH and route acceptance.
   - Provided instructions for placing and managing the script in `/root/`.

---

## 2. Herdr Workspace & Tab Operations

### Discovery and Command Syntax
- Herdr exposes tab manipulation under `herdr tab [COMMAND]`.
- Syntax: `herdr tab rename <TAB_ID> <LABEL>...`
- Herdr injects environment variables for caller context:
  - `HERDR_WORKSPACE_ID`: `w1`
  - `HERDR_TAB_ID`: `w1:t2` (current tab where this agent was invoked)
  - `HERDR_PANE_ID`: `w1:p6`

### Tab Inventory & Mutation
Querying `herdr tab list --workspace "$HERDR_WORKSPACE_ID"` returned:
- `w1:t1`: Tab #1 (originally labeled `"1"`, containing 3 panes)
- `w1:t2`: Tab #2 (labeled `"gDoc P"`, containing 1 pane)
- `w1:t4`: Tab #4 (labeled `"run_mosh"`, containing 1 pane)

**Action Executed:**
```bash
herdr tab rename w1:t1 "Assembly A26-2"
```
The label update was confirmed with response `tab_info` acknowledging `Assembly A26-2`.

---

## 3. Remote Fleet Connectivity Diagnostics

### Fleet Machines Inspected in Herdr
- `c8f0d456eaedd772caf1c32ffcf0f099`: `ap-elite` (`alan@100.110.200.56`)
- `92edac77d7831c591328160167ebacf4`: `ap-macbook` (`alan@100.87.229.122`)
- `27c778a6371dc1a504715ed858f750d8`: `rp4-2gb` (`alan@100.93.253.59`)
- `6361494f6d155a78c37601f7731628fa`: `aws-caddy` (`ec2-user@100.88.201.57`)

### Diagnostic Findings

#### 1. `ap-elite`
- **Initial Error:** `noninteractive SSH command timed out`.
- **Root Cause Analysis:**
  1. *Tailscale SSH Check Mode:* Non-interactive automated connections were gated by Tailscale SSH security check URLs (`https://login.tailscale.com/a/...`), requiring browser approval.
  2. *Non-login `PATH` Evaluation:* Herdr initiates sessions via `/bin/sh -s`. On `ap-elite`, Herdr was installed in `/home/alan/.local/bin/herdr`, whereas non-login SSH environments evaluate `/usr/local/bin:/usr/bin:/bin`, yielding `herdr: command not found`.
  3. *Raw IP vs MagicDNS:* Connecting to raw IP `100.110.200.56` encountered packet timeouts, whereas connecting via MagicDNS (`alan@ap-elite.manee-dab.ts.net`) was routed directly via Tailscale SSH.
- **Resolution & Verification:**
  - Authenticated Tailscale SSH and created system symlink:
    ```bash
    ssh alan@ap-elite.manee-dab.ts.net "sudo ln -sf /home/alan/.local/bin/herdr /usr/local/bin/herdr"
    ```
  - Ran `herdr machine status ap-elite --json`, which updated to:
    ```json
    {
      "id": "c8f0d456eaedd772caf1c32ffcf0f099",
      "label": "ap-elite",
      "status": "reachable",
      "error": null
    }
    ```
  - Verified remote execution: `herdr --machine ap-elite pane list` returned live panes `w2:p1` and `w3:pA`.

#### 2. `ap-macbook`
- **Observed Behavior:** Intermittent connectivity (`reachable` during initial test, transitioning to `remote platform detection failed: ssh: connect to host 100.87.229.122 port 22: Connection timed out`).
- **Root Cause:** macOS sleep / power management disconnecting network interfaces and SSH listening sockets when the lid is closed or the host enters power nap. When awake, Herdr API forwarding operates normally (detected active `agy` agent session in pane `w1:p1`).

#### 3. `rp4-2gb`
- **Observed Behavior:** Always online and reachable (`status: reachable`).
- **Explanation:** Always-on Linux SBC running continuous power, permanent Tailscale daemon, and systemd SSH daemon with persistent sockets.

---

## 4. Tailscale Daemon Automation (`start-tailscale.sh`)

### Purpose
Provide a standardized script to start and manage `tailscaled` and ensure the Tailscale network link is brought online across different environments (native Linux host, containers, or minimal environments without systemd).

### Script Implementation: `start-tailscale.sh`
Located at: [`start-tailscale.sh`](file:///home/alanp2/GitHub/ap-devices-and-pcs/start-tailscale.sh)

**Key Features:**
1. **Root Verification:** Enforces execution under root or `sudo`.
2. **Dual-Mode Daemon Management:**
   - *Systemd Mode:* Detects active systemd and uses `systemctl start tailscaled`.
   - *Standalone/Direct Mode:* For non-systemd or container setups, creates necessary state and run directories (`/var/run/tailscale`, `/var/lib/tailscale`) and launches `tailscaled` directly in background with output directed to `/var/log/tailscaled.log`.
3. **State Verification and Link Bring-up:**
   - Evaluates `tailscale status`.
   - If stopped, automatically executes `tailscale up --ssh --accept-routes`.
   - Flags if `NeedsLogin` is required or confirms active IP connection.

### Root Deployment Instructions
To install into `/root/`:
```bash
sudo cp /home/alanp2/GitHub/ap-devices-and-pcs/start-tailscale.sh /root/start-tailscale.sh
sudo chmod +x /root/start-tailscale.sh
```

---

## 5. Artifacts and Changes Summary

| File / Component | Type | Description |
| :--- | :--- | :--- |
| `start-tailscale.sh` | Shell Script | Root/sudo automated launcher for `tailscaled` and `tailscale up` |
| `docs/session_notes_2026-11-06_herdr_tabs_machine_connectivity_and_tailscale_daemon.md` | Documentation | This document recording recent session activities |
| `ap-elite:/usr/local/bin/herdr` | Remote Symlink | Symlinked to `/home/alan/.local/bin/herdr` on `ap-elite` |
| Herdr Tab `w1:t1` | Configuration | Renamed from `"1"` to `"Assembly A26-2"` |
