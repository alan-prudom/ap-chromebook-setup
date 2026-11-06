# Engineering & Session Notes: Disk Space Reclamation, UV Update, and Python 3.14 Environment Alignment

**Date:** 2026-11-06  
**Repository:** `alan-prudom/ap-devices-and-pcs`  
**Related Components:** System Storage (`/dev/vdb`), `uv` Package Manager, Python Runtime Environment, Systemd Journal

---

## 1. Executive Summary

This session executed three primary maintenance and configuration actions on the workstation environment:
1. **Disk Capacity Audit and Space Reclamation**:
   - Diagnosed root filesystem pressure (`/dev/vdb` was at 92% utilization with only 833 MB free out of 10 GB).
   - Identified high-impact, disposable caches across user packages, headless browser binaries, and archived system logs.
   - Reclaimed **2.5 GB** of storage, reducing disk utilization from **92% down to 67%** (free space increased to 3.3 GB, a 4x increase).
2. **`uv` Package Manager Verification & Upgrade**:
   - Verified active `uv` binary at `~/.local/bin/uv`.
   - Executed `uv self update`, successfully updating `uv` from `0.13.6` to latest `0.13.7`.
3. **Python Runtime Audit & Priority Configuration**:
   - Audited all available Python runtimes via `uv python list` and system inspection.
   - Verified that `cpython-3.14.10-linux-x86_64-gnu` is the **only** UV-managed Python installed on the host (`~/.local/share/uv/python/cpython-3.14.10-linux-x86_64-gnu`).
   - Noted Debian base system requirement (`/usr/bin/python3.13` from `python3.13-minimal` needed for apt and systemd).
   - Created user symlinks in `~/.local/bin/` (`python` and `python3` -> `python3.14`) to ensure shell commands default directly to UV Python 3.14.10 instead of the Debian system interpreter.

---

## 2. Disk Space Audit & Cleanup Metrics

### Initial State
- **Partition:** `/dev/vdb` (10 GB)
- **Used:** 9.0 GB (92%)
- **Available:** 833 MB (8%)

### Identified Large Directories
1. `~/.cache/uv/` (~730 MB): UV package wheel and build caches, including `.tmp*` directories.
2. `~/.cache/ms-playwright/` (~681 MB): Cached Chromium test binaries (`chromium-1248` and `chromium_headless_shell-1248`).
3. `/var/log/journal/` (~644 MB): Rotated and archived systemd journal files.
4. `~/.npm/` (~448 MB): NPM global package download cache and temporary `_npx` installations.
5. `/var/cache/apt/` (~284 MB): Downloaded Debian `.deb` package archives.
6. `~/.cache/agentsview/` (~178 MB): Binary cache for AgentsView.

### Actions Executed
```bash
# 1. Cleaned user caches
uv cache clean 2>/dev/null || rm -rf ~/.cache/uv
rm -rf ~/.cache/ms-playwright
npm cache clean --force 2>/dev/null || rm -rf ~/.npm
rm -rf ~/.cache/agentsview

# 2. Vacuumed system logs and cleaned package cache
sudo journalctl --vacuum-size=50M
sudo apt-get clean
```

### Resulting Storage State
- **Used:** 6.5 GB (67%)
- **Available:** 3.3 GB (33%)
- **Total Space Reclaimed:** **2.5 GB**

---

## 3. UV & Python Runtime Verification

### `uv` Upgrade
- **Command:** `uv self update`
- **Output:**
  ```text
  info: Checking for updates...
  success: Upgraded uv from v0.13.6 to v0.13.7! https://github.com/astral-sh/uv/releases/tag/0.13.7
  ```
- **Binary:** `/home/alanp2/.local/bin/uv` (`uv 0.13.7 (x86_64-unknown-linux-gnu)`)

### Python 3.14 Verification
Running `uv python list` confirmed:
- UV-installed version: `cpython-3.14.10-linux-x86_64-gnu`
- Path: `/home/alanp2/.local/share/uv/python/cpython-3.14.10-linux-x86_64-gnu/bin/python3.14`
- Existing symlink: `/home/alanp2/.local/bin/python3.14`

### Priority Path Alignment
To prevent accidental invocation of Debian's system Python (`/usr/bin/python3.13`) when running bare commands:
```bash
ln -sf ~/.local/bin/python3.14 ~/.local/bin/python
ln -sf ~/.local/bin/python3.14 ~/.local/bin/python3
```

**Verification:**
- `which python` &rarr; `/home/alanp2/.local/bin/python` (`Python 3.14.10`)
- `which python3` &rarr; `/home/alanp2/.local/bin/python3` (`Python 3.14.10`)
- `which python3.14` &rarr; `/home/alanp2/.local/bin/python3.14` (`Python 3.14.10`)
- `.python-version` in repository: `3.14`

---

## 4. Manifest and Environment Summary

| Item | Previous State | Current State |
| :--- | :--- | :--- |
| **Disk Available (`/`)** | 833 MB (92% used) | **3.3 GB** (67% used, +2.5 GB free) |
| **`uv` Version** | `0.13.6` | **`0.13.7` (latest)** |
| **Installed UV Python** | Python 3.14.10 | **Python 3.14.10 (only)** |
| **Shell `python` Command** | Unlinked | **`~/.local/bin/python` &rarr; Python 3.14.10** |
| **Shell `python3` Command** | `/usr/bin/python3` (3.13.5) | **`~/.local/bin/python3` &rarr; Python 3.14.10** |
