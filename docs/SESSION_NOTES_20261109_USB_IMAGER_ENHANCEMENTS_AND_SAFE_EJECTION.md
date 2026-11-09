# Session Notes: Crostini USB Imager Enhancement & Safe Ejection Workflow

**Date:** 2026-11-09  
**Host / Device:** Chromebook (`penguin` Crostini VM container)  
**Workspace:** `~/GitHub/ap-devices-and-pcs/devices/ap-chromebook-setup`  
**Primary File Modified:** [`image-usb.sh`](../image-usb.sh)

---

## 1. Context & Incident Summary

During an attempted raw block backup of a SanDisk Ultra USB 3.0 device (`/dev/sda`, 28.6 GiB raw disk capacity), `zstd` terminated mid-stream with:
```text
zstd: error 70 : Write error : cannot write block : No space left on device
16.9GiB 0:04:12 [68.3MiB/s] [===============>            ]  58%
```

### Root Cause Analysis
1. **Container vs. USB Disk Capacity:**
   - The Linux VM root partition (`/dev/vdb` formatted as `btrfs`) had ~28.5–29 GiB free space.
   - The USB flash drive was 28.6 GiB raw unpartitioned/partitioned disk space containing ChromeOS recovery partitions (`ROOT-A`, `OEM`, `EFI-SYSTEM`, etc.), which hold pre-compressed and encrypted blocks.
   - Because `zstd` cannot effectively compress non-compressible or random block data, the stream reached ~17 GiB before exceeding available storage boundaries or hitting Btrfs allocation chunks.
2. **Failure Handling:**
   - When a pipe in `dd | pv | zstd > file` breaks, the partial output file was remaining on disk without clean teardown.
3. **Workflow & UX Friction:**
   - Single external USB device was detected, but user still had to manually type `/dev/sda`.
   - Running an operation (like testing device accessibility or backup) caused the script to exit immediately (`break` from `select`), requiring the user to relaunch the script every time.
   - No clear guidance on how to safely disconnect/eject raw USB block devices shared through ChromeOS Crostini USB passthrough.

---

## 2. Key Discussion Points & User Decisions

1. **Disk Space Verification:**
   - *User Decision:* Option 1 (**Warn mode**).
   - Check available filesystem disk space against the raw device size.
   - If available space is less than the raw block size, display a prominent warning banner explaining that compression reduces size, but uncompressible data might fill the disk, and prompt the user to confirm `(y/N)` before starting.
2. **Destination Path Selection:**
   - *User Decision:* Option 2 (**No** to extra destination path prompts/Google Drive complexity for now).
   - Retain standard home directory default (`~/usb_backup_YYYYMMDD_HHMMSS.img.zst`) with clean user resolution via `SUDO_USER` / `getent passwd`.
3. **Auto-Defaulting Single Detected USB Devices:**
   - External candidate devices (excluding `/` root disk `vdb` and tools disk `vda`) are enumerated.
   - If exactly one USB disk exists, automatically propose it as default: `Enter source block device [/dev/sda]: ` so pressing `Enter` confirms it.
4. **Interactive Menu Loopback:**
   - Wrap the main menu in a `while true` loop.
   - When an operation (Backup, Restore, or Accessibility test) finishes, pause with `Press Enter to return to main menu...` rather than exiting to shell.
   - Explicit exit only via Option 4 (`Quit`) or `Ctrl+C`.
5. **Partial File Cleanup on Error / Interruption:**
   - Added signal traps (`INT`, `TERM`) to delete incomplete `.img.zst` files if aborted or if the command pipeline fails.
6. **Celebratory Completion Message & Safe USB Ejection Instructions:**
   - When backup finishes successfully and SHA-256 is generated, print a styled completion banner followed by step-by-step instructions for safely ejecting the device in ChromeOS.

---

## 3. Changes Implemented in `image-usb.sh`

### A. Candidate USB Detection (`get_usb_candidates`)
Added helper function that filters out system virtual block devices (`vda`, `vdb`, or active root disk source):
```bash
get_usb_candidates() {
    local root_dev
    root_dev=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE / 2>/dev/null)" 2>/dev/null || true)
    [[ -z "$root_dev" ]] && root_dev=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's|^/dev/||')

    local candidates=()
    while IFS= read -r name; do
        [[ -n "$name" ]] && candidates+=("/dev/$name")
    done < <(lsblk -d -n -o NAME,TYPE | grep -E "disk" | grep -v -E "(${root_dev:-vdb}|vda)" | awk '{print $1}')

    echo "${candidates[@]}"
}
```

### B. Defaulting Prompts
In Backup, Restore, and Test options:
- Detect candidate count:
  ```bash
  candidates=($(get_usb_candidates))
  default_dev=""
  if [[ ${#candidates[@]} -eq 1 ]]; then
      default_dev="${candidates[0]}"
  fi
  ```
- Prompt uses default if present:
  ```bash
  read -rp "Enter source block device [$default_dev]: " SRC_DEV
  SRC_DEV="${SRC_DEV:-$default_dev}"
  ```

### C. Disk Free Space Pre-flight Check
Checks destination directory space before starting transfer:
```bash
AVAIL_BYTES=$(df -B1 "$DEST_DIR" | awk 'NR==2 {print $4}')
AVAIL_HR=$(df -h "$DEST_DIR" | awk 'NR==2 {print $4}')

if [[ "$AVAIL_BYTES" -lt "$DEV_SIZE" ]]; then
    echo ""
    echo -e "${YELLOW}[WARNING] Destination filesystem free space ($AVAIL_HR) is less than the raw device size ($DEV_SIZE_HR).${NC}"
    echo -e "${YELLOW}          Compression with zstd will reduce image size, but if the disk holds uncompressible data,${NC}"
    echo -e "${YELLOW}          the backup could run out of disk space mid-stream.${NC}"
fi
```

### D. Signal Trapping & Failure Cleanup
```bash
trap 'rm -f "$OUT_FILE"; echo -e "\n${RED}[!] Backup aborted. Partial file removed.${NC}"; exit 1' INT TERM

if dd if="$SRC_DEV" bs=4M status=none \
    | pv -s "$DEV_SIZE" \
    | zstd -T0 -3 > "$OUT_FILE"; then
    trap - INT TERM
    sync
    ...
else
    trap - INT TERM
    rm -f "$OUT_FILE"
    echo -e "${RED}[ERROR] Backup failed. Partial file removed.${NC}"
fi
```

### E. Completion Banner & Safe USB Eject Instructions
Upon completion of image creation and checksum calculation:
```bash
echo ""
echo -e "${GREEN}===================================================================${NC}"
echo -e "${GREEN}                  🎉 Backup Successfully Created!                  ${NC}"
echo -e "${GREEN}===================================================================${NC}"
echo -e "[*] Generating SHA-256 checksum..."
sha256sum "$OUT_FILE" | tee "${OUT_FILE}.sha256"

if [[ -n "${SUDO_USER:-}" ]]; then
    chown "$SUDO_USER:$SUDO_USER" "$OUT_FILE" "${OUT_FILE}.sha256"
fi

echo ""
echo -e "${BLUE}--- Safe USB Eject Instructions ---${NC}"
echo -e "To safely disconnect your USB drive:"
echo -e "  1. Open ChromeOS ${YELLOW}Settings${NC} -> ${YELLOW}Advanced${NC} -> ${YELLOW}Developers${NC} -> ${YELLOW}Linux${NC}"
echo -e "  2. Click '${YELLOW}Manage USB devices${NC}' and toggle your USB drive ${YELLOW}OFF${NC}"
echo -e "  3. Open the ChromeOS ${YELLOW}Files${NC} app and click the ${YELLOW}Eject (⏏)${NC} icon next to the drive"
echo -e "  4. Unplug the drive when ChromeOS notifies it is safe to remove."
echo -e "${GREEN}===================================================================${NC}"
```

### F. Persistent Menu Loop
Wrapped menu operations in a `while true` loop. Each action breaks only from the inner `select`, then pauses:
```bash
    echo ""
    read -rp "Press Enter to return to main menu..." _dummy
    echo ""
done
```

---

## 4. Verification & Testing

- Syntax checked via `bash -n image-usb.sh` (passed).
- Successful full device backup completed:
  - Device: `/dev/sda` (28.6 GiB)
  - Time elapsed: 0:07:23 at ~66.1 MiB/s
  - Output image: `/home/alanp2/usb_backup_20261109_093411.img.zst`
  - Checksum: `dd22af4129e446e48fc73349e5b71f043e18a9edc367b9329b85d3a72b2f66b7`
- Verified block device cache flushing (`sync`).
