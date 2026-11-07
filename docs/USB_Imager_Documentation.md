# Crostini USB Imager (`usb-imager.sh`) User Guide

`usb-imager.sh` is an interactive, fail-safe utility built for ChromeOS Crostini (Linux container) environments to create and restore bit-for-bit raw block images of physical USB storage devices.

It integrates high-throughput compression (`zstd`), live rate-monitoring (`pv`), cryptographic integrity auditing (`sha256sum`), and safety tripwires to prevent accidental host system disk overwrites.

---

## 1. Prerequisites & Environment Setup

ChromeOS defaults to sharing USB devices as user-space file mounts (`/mnt/chromeos/removable/...`). To clone partition tables, EFI system partitions, bootloaders, and unallocated sectors, the raw USB block device must be passed directly into the Crostini container.

### 1.1 Exposing Raw USB Blocks to Linux
1. Insert the target USB storage device into your Chromebook.
2. Open ChromeOS **Settings** $\rightarrow$ **About ChromeOS** $\rightarrow$ **Linux development environment**.
3. Select **Manage USB devices**.
4. Locate your USB device in the list and toggle the switch to **ON**.
5. Inside the Crostini Terminal, run:
   ```bash
   lsblk -d -o NAME,SIZE,TYPE,VENDOR,MODEL,TRAN
   ```
   Confirm that your physical device appears as an independent SCSI/SATA disk (typically `/dev/sdb`, `/dev/sdc`, etc.) distinct from the virtual root device (`/dev/vda`).

---

## 2. Installation & Permissions

Place the script in your Crostini home directory or local binaries path:

```bash
# Save or move the script
nano ~/usb-imager.sh

# Grant execution permissions
chmod +x ~/usb-imager.sh
```

The script can be invoked as an unprivileged user; it detects lack of root privileges and automatically requests `sudo` escalation.

---

## 3. Built-In Safety Guardrails

Because low-level block imaging via `dd` can destroy system partitions if configured with the wrong target, `usb-imager.sh` incorporates multiple protective barriers:

| Protection | Implementation | Failure Mode Prevented |
| :--- | :--- | :--- |
| **System Root Tripwire** | Evaluates target device against active mountpoints (`/`, `/boot`, `/etc`). | Aborts execution immediately if the user specifies the container's root disk (`/dev/vda`). |
| **Block Node Verification** | Verifies target is a valid block device (`[[ -b "$dev" ]]`). | Prevents accidentally targeting raw files, non-block mounts, or non-existent paths. |
| **Strict Type-to-Confirm** | Requires typing the exact target block string (e.g. `/dev/sdb`) during restore. | Prevents accidental keypresses (`Enter` or `y`) from triggering a disk overwrite. |
| **Pre-Flight Integrity Audit** | Detects accompanying `.sha256` files and validates checksums before writing. | Prevents writing corrupted or truncated image archives to physical media. |
| **I/O Sync Guarantees** | Implements `conv=fsync` and kernel `sync`. | Prevents data corruption caused by prematurely disconnecting USB devices while dirty pages remain in RAM cache. |

---

## 4. Step-by-Step Usage

Run the tool:
```bash
~/usb-imager.sh
```

The script starts by scanning block devices and presenting an interactive menu:

```text
==========================================
       Crostini Raw USB Disk Utility      
==========================================
Available storage block devices:

NAME SIZE TYPE VENDOR MODEL TRAN MOUNTPOINTS
vda   16G disk                   /
sdb   32G disk SanDisk Ultra  usb 

Select an operation (1-3): 
1) Backup USB Drive to .img.zst
2) Restore .img.zst to USB Drive
3) Quit
```

---

### 4.1 Creating an Image (Backup)

1. Select option **`1`**.
2. **Specify Source:** Enter the path to the USB disk (e.g., `/dev/sdb`).
3. **Specify Destination:** Accept the default timestamped path (`~/usb_backup_YYYYMMDD_HHMMSS.img.zst`) or enter a custom path (e.g., on a secondary drive or Google Drive shared mount).
4. **Confirm Action:** Review the disk capacity and target location, then press `y`.
5. **Execution:** `pv` displays real-time compression rate, processed bytes, and estimated completion time.
6. **Integrity Checksum:** Upon completion, the script automatically writes a `.sha256` digest alongside the generated image.

---

### 4.2 Restoring an Image (Write to Disk)

> ⚠️ **CRITICAL WARNING:** Restoring completely wipes all partitions, filesystems, and partition tables on the selected physical drive.

1. Select option **`2`**.
2. **Specify Source Archive:** Enter the path to your `.img.zst` file.
3. **Integrity Audit:** If a `.sha256` file is present in the same directory, the script verifies file integrity. If the hash fails, the process terminates immediately without modifying the disk.
4. **Specify Target Block Device:** Enter the destination drive (e.g., `/dev/sdb`).
5. **Type Confirmation:** A warning banner appears. Type the exact target string (e.g., `/dev/sdb`) to unlock the write routine.
6. **Completion:** The script restores the exact partition layout and flushes buffers via `sync`.

---

## 5. Storage & Transfer Recommendations

* **Handling Large Drives:** `zstd -T0 -3` dynamically leverages all virtual CPU threads assigned to Crostini, giving fast compression without maxing out CPU resources.
* **Saving to External Locations:** If your Crostini container disk space is constrained, you can point the destination path directly to a secondary external drive or an SD card shared with Linux under `/mnt/chromeos/removable/<DriveName>/`.
* **Zero-Filling Unallocated Space (Optional):** To improve compression on filesystem-heavy drives, write a temporary file of zeroes across the source filesystem and delete it before imaging. This allows `zstd` to compress unallocated space to near-zero bytes.