# Crostini USB Imager (`image-usb.sh`) User Guide

`image-usb.sh` is an interactive, fail-safe utility built for ChromeOS Crostini (Linux container) environments to create and restore bit-for-bit raw block images of physical USB storage devices.

It integrates high-throughput compression (`zstd`), live rate-monitoring (`pv`), cryptographic integrity auditing (`sha256sum`), disk free-space pre-flight verification, automated USB block device detection, and safety tripwires to prevent accidental host system disk overwrites.

---

## 1. Prerequisites & Environment Setup

ChromeOS defaults to sharing USB devices as user-space file mounts (`/mnt/chromeos/removable/...`). To clone partition tables, EFI system partitions, bootloaders, and unallocated sectors, the raw USB block device must be passed directly into the Crostini container.

### 1.1 Exposing Raw USB Blocks to Linux
1. Insert the target USB storage device into your Chromebook.
2. Open ChromeOS **Settings** $\rightarrow$ **Advanced** $\rightarrow$ **Developers** $\rightarrow$ **Linux development environment**.
3. Select **Manage USB devices**.
4. Locate your USB device in the list and toggle the switch to **ON**.
5. Inside the Crostini Terminal, run:
   ```bash
   lsblk -d -o NAME,SIZE,TYPE,VENDOR,MODEL,TRAN
   ```
   Confirm that your physical device appears as an independent SCSI/SATA disk (typically `/dev/sda`, `/dev/sdb`, etc.) distinct from the virtual container disks (`/dev/vda`, `/dev/vdb`).

---

## 2. Installation & Permissions

The utility is located directly in the `ap-chromebook-setup` repository:

```bash
# Grant execution permissions if needed
chmod +x ./image-usb.sh

# Run the utility
./image-usb.sh
```

The script can be invoked as an unprivileged user; it detects lack of root privileges and automatically requests `sudo` escalation.

---

## 3. Built-In Safety Guardrails

Because low-level block imaging via `dd` can destroy system partitions if configured with the wrong target, `image-usb.sh` incorporates multiple protective barriers:

| Protection | Implementation | Failure Mode Prevented |
| :--- | :--- | :--- |
| **System Root Tripwire** | Evaluates target device against active mountpoints (`/`, `/boot`, `/etc`). | Aborts execution immediately if the user specifies the container's root disk (`/dev/vda` or `/dev/vdb`). |
| **Block Node Verification** | Verifies target is a valid block device (`[[ -b "$dev" ]]`). | Prevents accidentally targeting raw files, non-block mounts, or non-existent paths. |
| **Auto USB Candidate Detection** | Filters out container root disks and detects non-system drives. | Defaults prompt to single detected USB disk (e.g. `/dev/sda`) to eliminate manual typos. |
| **Pre-Flight Disk Space Check** | Compares target filesystem free space (`df -B1`) with raw disk size. | Warns user before imaging if container free space is lower than raw capacity, preventing mid-stream exhaustion. |
| **Partial Archive Cleanup Trap** | Registers `INT` and `TERM` traps to remove incomplete files on error/abort. | Prevents dead gigabytes of partial `.img.zst` files filling the container on failure. |
| **Strict Type-to-Confirm** | Requires typing the exact target block string (e.g. `/dev/sda`) during restore. | Prevents accidental keypresses (`Enter` or `y`) from triggering a disk overwrite. |
| **Pre-Flight Integrity Audit** | Detects accompanying `.sha256` files and validates checksums before writing. | Prevents writing corrupted or truncated image archives to physical media. |
| **I/O Sync Guarantees** | Implements `conv=fsync` and kernel `sync`. | Prevents data corruption caused by prematurely disconnecting USB devices while dirty pages remain in RAM cache. |

---

## 4. Step-by-Step Usage

Run the tool:
```bash
./image-usb.sh
```

The script starts by scanning block devices and presenting an interactive menu wrapped in a continuous loop:

```text
==========================================
       Crostini Raw USB Disk Utility      
==========================================
Available storage block devices & partitions:

NAME     SIZE TYPE VENDOR   MODEL         LABEL         MOUNTPOINTS       FSTYPE
sda     28.6G disk SanDisk  Ultra USB 3.0                                 
├─sda1   9.3M part                                                        ext2
├─sda3   3.5G part                        ROOT-A                          ext4
...
vda     68.6M disk 0x1af4                 cros-vm-tools /opt/google/cros-containers
vdb       35G disk 0x1af4                               /                 btrfs

Select an operation (1-4): 
1) Backup USB Drive to .img.zst
2) Restore .img.zst to USB Drive
3) Test USB Drive Accessibility
4) Quit
```

---

### 4.1 Creating an Image (Backup)

1. Select option **`1`**.
2. **Source Device:** If exactly one external device is present, press `Enter` to accept the default `[/dev/sda]`.
3. **Destination Path:** Accept the timestamped default (`~/usb_backup_YYYYMMDD_HHMMSS.img.zst`) or enter a custom path.
4. **Pre-flight Space Audit:** The summary displays:
   - Source device & capacity
   - Target path
   - Available filesystem space
   - If available space is less than raw capacity, a warning is printed advising of potential uncompressible data exhaustion.
5. **Confirm:** Enter `y` to proceed.
6. **Live Stream:** `pv` displays throughput, transfer progress, and elapsed time.
7. **Completion & Eject Guide:** Displays a celebratory finish banner, calculates the SHA-256 digest, and presents step-by-step instructions for safely ejecting the device in ChromeOS before returning to the main menu.

---

### 4.2 Restoring an Image (Write to Disk)

> ⚠️ **CRITICAL WARNING:** Restoring completely wipes all partitions, filesystems, and partition tables on the selected physical drive.

1. Select option **`2`**.
2. **Specify Source Archive:** Enter the path to your `.img.zst` file.
3. **Integrity Audit:** If a `.sha256` file is present in the same directory, the script automatically verifies file integrity before touching the disk.
4. **Specify Target Block Device:** Press `Enter` to accept the detected USB default (e.g. `[/dev/sda]`) or specify the device.
5. **Type Confirmation:** A destructive warning banner appears. Type the exact target string (e.g. `/dev/sda`) to unlock the write routine.
6. **Completion:** The script writes the bit-level stream, synchronizes filesystem caches, and safely reports completion.

---

### 4.3 Testing USB Drive Accessibility

1. Select option **`3`**.
2. Accepts detected USB device default.
3. Performs read test of the first 1MB (`dd if="$dev" of=/dev/null bs=1M count=1`), verifies partition table detection, and prints device health before returning to the menu.

---

## 5. Safely Ejecting the USB Device in ChromeOS

After imaging completes, raw USB block passthrough must be released cleanly before physical removal:
1. Open ChromeOS **Settings** $\rightarrow$ **Advanced** $\rightarrow$ **Developers** $\rightarrow$ **Linux**.
2. Click **Manage USB devices**.
3. Toggle the physical USB device switch to **OFF** (releases passthrough back to ChromeOS).
4. Open the ChromeOS **Files** app and click the **Eject (⏏)** icon next to the drive in the sidebar.
5. Unplug the drive once ChromeOS notifies it is safe to remove.

---

## 6. Storage & Transfer Recommendations

* **Handling Large Drives:** `zstd -T0 -3` dynamically leverages all virtual CPU threads assigned to Crostini, giving fast compression without maxing out CPU resources.
* **Saving to External Locations:** If your Crostini container disk space is constrained, point the destination path to a secondary external drive or an SD card shared with Linux under `/mnt/chromeos/removable/<DriveName>/`.
* **Zero-Filling Unallocated Space (Optional):** To maximize compression efficiency on filesystem-heavy drives, write zeroes across unallocated space before imaging (`dd if=/dev/zero of=zero.fill bs=1M status=progress; rm -f zero.fill`).