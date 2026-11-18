# Session Notes: SSH Connectivity, Tailscale Stabilization, Android Bridge, and Mobile Storage Automation

**Date**: 2026-11-13 – 2026-11-18  
**Device Context**: Chromebook (`penguin` Debian container via Crostini), MacBook Air (`ap-macbook`), Pixel 7 Pro, Samsung Galaxy S23 Ultra  
**Network**: Tailnet (Tailscale WireGuard mesh)

---

## 1. Executive Summary
During this session, we accomplished major infrastructure, automation, and cross-device mobile management milestones across the Chromebook and connected devices:
1. **Passwordless SSH from `ap-macbook`**: Configured and enabled OpenSSH daemon inside Crostini, verified IP binding over Tailscale (`100.102.167.71`), and updated startup scripting.
2. **Tailscale & SSH Automation Script (`start_tailscale.sh`)**: Enhanced the startup automation script to check and auto-start `ssh.service`, eliminate transient startup race conditions (`NoState`), output connection IPs, and linked `~/start-tailscale.sh` via symlink.
3. **ChromeOS Android Tailscale Stabilization**: Resolved background suspension issues on ChromeOS's Android Tailscale app by enabling ADB bridge debugging and programmatically whitelisting `com.tailscale.ipn` against Doze, background memory reclamation, and binding it as `always_on_vpn_app`.
4. **Multi-Phone Wireless ADB Connectivity**: Connected and paired both **Pixel 7 Pro** and **Samsung Galaxy S23 Ultra** wirelessly over Tailscale.
5. **Mobile Device Storage Reclamation**:
   - **Pixel 7 Pro**: Reclaimed **~15.7 GB** (deleted `hermes-workspace`, purged legacy WhatsApp and WhatsApp media, trimmed oldest 10 GB of Pocket Casts episodes).
   - **Samsung Galaxy S23 Ultra**: Reclaimed **~37.3 GB** (purged `hermes-workspace`, deleted oldest 20.5 GB of Pocket Casts audio, and transferred 12 priority voice recordings totaling ~13 GB).
6. **Verified USB Archival Pipeline**: Configured exFAT filesystem support, mounted an external 120 GB USB drive (`/dev/sda1` -> `/mnt/usb`), installed Audacity on Crostini, and migrated 12 large audio recordings with strict end-to-end MD5 checksum validation before deletion.
7. **FUSE Filesystem Mounting (`adbfs-rootless`)**: Compiled and installed `adbfs-rootless`, mounting the Pixel 7 Pro storage directly into the Linux filesystem (`~/phone_pixel` and `~/pixel_storage`) for native CLI file inspection and editing.

---

## 2. Detailed Technical Workflows & File Changes

### A. Tailscale & SSH Service Script Enhancement (`start_tailscale.sh`)
- **File**: `start_tailscale.sh` (symlinked from `~/start-tailscale.sh`)
- **Git Diff**:
  - Added verification and auto-start logic for `ssh.service` via `systemctl` / `service`.
  - Added a 10-second polling retry loop to handle the transient `unexpected state: NoState` / `Tailscale is starting` race condition.
  - Automatically queries and prints the container's Tailscale IPv4 address and direct SSH login syntax (`ssh alanp2@<ip>`).

### B. ChromeOS Android Subsystem Optimization via ADB
To prevent ChromeOS low-memory killer (LMK) and sleep suspend from killing the Android Tailscale VPN app (`com.tailscale.ipn`):
1. Enabled ChromeOS Developer Android ADB Bridge (`100.115.92.2:5555`).
2. Whitelisted Tailscale from Android battery optimization / Doze:
   ```bash
   adb -s 100.115.92.2:5555 shell dumpsys deviceidle whitelist +com.tailscale.ipn
   ```
3. Enabled unrestricted background operation (`appops`):
   ```bash
   adb -s 100.115.92.2:5555 shell cmd appops set com.tailscale.ipn RUN_ANY_IN_BACKGROUND allow
   adb -s 100.115.92.2:5555 shell cmd appops set com.tailscale.ipn RUN_IN_BACKGROUND allow
   ```
4. Locked Tailscale as the persistent system VPN:
   ```bash
   adb -s 100.115.92.2:5555 shell settings put secure always_on_vpn_app com.tailscale.ipn
   ```

---

### C. Wireless ADB Device Pairing over Tailscale
Both mobile devices were paired and connected wirelessly through Tailscale IPs:
- **Pixel 7 Pro (`cheetah`)**:
  - Tailscale IP: `100.109.50.66`
  - Paired on port `41199`, connected via active port `44487`.
- **Samsung Galaxy S23 Ultra (`SM-S918B` / `dm3q`)**:
  - Tailscale IP: `100.83.231.36`
  - Paired on port `35597`, connected via active port `33101`.

---

### D. Samsung S23 Ultra Storage & Verified USB Archival Pipeline

#### 1. Hardware & System Setup:
- Installed `exfat-fuse` and `exfatprogs` inside Crostini.
- Mounted raw passthrough USB drive `/dev/sda1` to `/mnt/usb/Recordings_S23_Backup/`.
- Installed **Audacity** (`audacity 3.7.3+dfsg-1`) on Crostini for native audio waveform editing.

#### 2. Deletions on S23 Ultra:
- Deleted `/storage/emulated/0/hermes-workspace` via `find -delete` (~4.9 GB reclaimed).
- Deleted oldest 20 GB of Pocket Casts episodes (391 files, ~20.5 GB reclaimed).

#### 3. Verified MD5 Archival Table (S23 Ultra -> USB Drive):
Each recording was pulled via ADB, hashed on both sides, verified to match 100%, and then removed from the phone:

| # | File Name | Size | Checksum (Phone == USB) | Verification | Deletion |
|---|---|---|---|---|---|
| 1 | `My recording 6.m4a` | 2.03 GB | `a0fded6eb56a834be8df0dcb27828c99` | Match ✅ | Deleted ✅ |
| 2 | `My recording 6_recovered (30).m4a` | 1.85 GB | `227fc4b6f65b43788727b5bb8848d901` | Match ✅ | Deleted ✅ |
| 3 | `My recording 6_recovered (23).m4a` | 1.12 GB | `260ef96b5a15401bafd1afd9b5027fcb` | Match ✅ | Deleted ✅ |
| 4 | `My recording 6_recovered (11).m4a` | 1.09 GB | `3b13e5381429133a038ef99738570897` | Match ✅ | Deleted ✅ |
| 5 | `My recording 364.m4a` | 1.02 GB | `1414037ad893d3646b10397ec3db10dd` | Match ✅ | Deleted ✅ |
| 6 | `My recording 184.m4a` | 982 MB | `74e56bf5510e2f23b38007496478f97f` | Match ✅ | Deleted ✅ |
| 7 | `My recording 6_recovered (12).m4a` | 883 MB | `9ccb13f4bcd9b27d46f9a325e0abd4b4` | Match ✅ | Deleted ✅ |
| 8 | `My recording 6_recovered (24).m4a` | 755 MB | `dbfd2f5c1c36643cbd8fd93872195abd` | Match ✅ | Deleted ✅ |
| 9 | `My recording 6_recovered (13).m4a` | 679 MB | `4f051dbed6c49ad9467c1b236dedd374` | Match ✅ | Deleted ✅ |
| 10 | `My recording 6_recovered (19).m4a` | 653 MB | `188f3800756617734696e5ae3d32499b` | Match ✅ | Deleted ✅ |
| 11 | `My recording 6_recovered (20).m4a` | 653 MB | `8cb344ff7f57bd7be8a61fc268eff83b` | Match ✅ | Deleted ✅ |
| 12 | `My recording 463.m4a` | 648 MB | `ed4064b4f1982a131920d9b344c4f805` | Match ✅ | Deleted ✅ |

- **Storage Result on S23 Ultra**: Free space increased from **1.7 GB (100% full)** to **39 GB (83% used)**, freeing **~37.3 GB**.

---

### E. FUSE Mount via `adbfs-rootless` (Pixel 7 Pro)
- Installed dependencies (`libfuse-dev`, `pkg-config`, `build-essential`).
- Built `adbfs-rootless` and copied binary to `/usr/local/bin/adbfs`.
- Mounted Pixel 7 Pro storage to `/home/alanp2/phone_pixel` and created symlink `~/pixel_storage`:
  ```bash
  export ANDROID_SERIAL="100.109.50.66:44487"
  adbfs /home/alanp2/phone_pixel
  ln -s /home/alanp2/phone_pixel/storage/emulated/0 ~/pixel_storage
  ```
- Files on Pixel 7 Pro are now directly accessible with standard Linux shell commands (`ls`, `grep`, `cp`, Audacity).

---

## 3. Current System State & Artifacts Summary

| Resource | State / Location | Description |
|---|---|---|
| **`start_tailscale.sh`** | [start_tailscale.sh](../start_tailscale.sh) | Updated with SSH check, IP display, and wait loop |
| **`~/start-tailscale.sh`** | Symlink to repo file | Enables immediate tracking of script edits |
| **Audacity** | Installed (`audacity`) | Audio editor with full Linux GUI & codec support |
| **Archived Recordings** | `/mnt/usb/Recordings_S23_Backup/` | 12 verified `.m4a` files (13 GB total) |
| **Pixel 7 Pro Mount** | `~/pixel_storage` | Live `adbfs` FUSE filesystem |
| **S23 Ultra Storage** | 39 GB Free (83% capacity) | Rescued from critical 100% exhaustion |
| **Pixel 7 Pro Storage** | 18 GB Free (84% capacity) | Cleaned up from 98% exhaustion |
