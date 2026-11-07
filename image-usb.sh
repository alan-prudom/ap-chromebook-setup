#!/usr/bin/env bash
#
# usb-imager.sh - Safe block device backup and restore utility for Crostini
#
set -euo pipefail

# --- Color formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Guard: Root Privileges ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}[!] Escalating to root privileges...${NC}"
    exec sudo bash "$0" "$@"
fi

# --- Guard: Dependency Check ---
ensure_deps() {
    local missing=()
    for cmd in zstd pv blockdev lsblk sha256sum; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}[*] Missing required packages: ${missing[*]}. Installing...${NC}"
        apt-get update -qq && apt-get install -y -qq zstd pv
    fi
}

# --- Guard: Protected Block Device Check ---
assert_safe_target() {
    local dev="$1"

    if [[ ! -b "$dev" ]]; then
        echo -e "${RED}[ERROR] Target '$dev' is not a valid block device.${NC}"
        exit 1
    fi

    # Block backup/restore if any partition on the device is mounted to / or /boot
    local mounts
    mounts=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null || true)
    while IFS= read -r mnt; do
        if [[ "$mnt" == "/" || "$mnt" == "/boot" || "$mnt" == "/etc" ]]; then
            echo -e "${RED}[FATAL] Safety tripwire: '$dev' holds the active system root ($mnt)! Operation aborted.${NC}"
            exit 1
        fi
    done <<< "$mounts"
}

# --- Menu / Selection ---
ensure_deps

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}       Crostini Raw USB Disk Utility      ${NC}"
echo -e "${BLUE}==========================================${NC}"
echo "Available storage block devices:"
echo ""
lsblk -d -o NAME,SIZE,TYPE,VENDOR,MODEL,TRAN,MOUNTPOINTS
echo ""

PS3="Select an operation (1-3): "
options=("Backup USB Drive to .img.zst" "Restore .img.zst to USB Drive" "Quit")
select opt in "${options[@]}"; do
    case $opt in
        "Backup USB Drive to .img.zst")
            read -rp "Enter source block device (e.g., /dev/sdb): " SRC_DEV
            assert_safe_target "$SRC_DEV"

            DEFAULT_OUT="${SUDO_USER:+/home/$SUDO_USER}/usb_backup_$(date +%Y%m%d_%H%M%S).img.zst"
            read -rp "Destination file path [$DEFAULT_OUT]: " OUT_FILE
            OUT_FILE="${OUT_FILE:-$DEFAULT_OUT}"

            # Ensure destination directory exists and is writable
            mkdir -p "$(dirname "$OUT_FILE")"

            DEV_SIZE=$(blockdev --getsize64 "$SRC_DEV")
            DEV_SIZE_HR=$(lsblk -dn -o SIZE "$SRC_DEV")

            echo ""
            echo -e "${YELLOW}--- Backup Summary ---${NC}"
            echo -e "Source:      ${GREEN}$SRC_DEV${NC} ($DEV_SIZE_HR)"
            echo -e "Destination: ${GREEN}$OUT_FILE${NC}"
            echo ""
            read -rp "Proceed with image creation? (y/N): " CONFIRM
            [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Operation canceled."; exit 0; }

            echo -e "${GREEN}[*] Imaging in progress... Press Ctrl+C to abort.${NC}"
            dd if="$SRC_DEV" bs=4M status=none \
                | pv -s "$DEV_SIZE" \
                | zstd -T0 -3 > "$OUT_FILE"

            sync
            echo -e "${GREEN}[✔] Backup complete!${NC}"
            echo -e "[*] Generating SHA-256 checksum..."
            sha256sum "$OUT_FILE" | tee "${OUT_FILE}.sha256"

            # Set correct ownership if run via sudo
            if [[ -n "${SUDO_USER:-}" ]]; then
                chown "$SUDO_USER:$SUDO_USER" "$OUT_FILE" "${OUT_FILE}.sha256"
            fi
            break
            ;;

        "Restore .img.zst to USB Drive")
            read -rp "Enter source .img.zst file path: " IMG_FILE
            if [[ ! -f "$IMG_FILE" ]]; then
                echo -e "${RED}[ERROR] File '$IMG_FILE' does not exist.${NC}"
                exit 1
            fi

            # Optional checksum verification
            if [[ -f "${IMG_FILE}.sha256" ]]; then
                echo -e "${YELLOW}[*] Checksum file found. Verifying archive integrity...${NC}"
                if ! (cd "$(dirname "$IMG_FILE")" && sha256sum -c "$(basename "${IMG_FILE}.sha256")"); then
                    echo -e "${RED}[FATAL] Checksum verification failed! The image is corrupted.${NC}"
                    exit 1
                fi
                echo -e "${GREEN}[✔] Image integrity verified.${NC}"
            fi

            read -rp "Enter destination block device (e.g., /dev/sdb): " DEST_DEV
            assert_safe_target "$DEST_DEV"

            DEST_SIZE=$(blockdev --getsize64 "$DEST_DEV")
            DEST_SIZE_HR=$(lsblk -dn -o SIZE "$DEST_DEV")

            echo ""
            echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
            echo -e "${RED}                   DESTRUCTIVE ACTION                   ${NC}"
            echo -e "${RED} This will PERMANENTLY ERASE all data on: $DEST_DEV ($DEST_SIZE_HR)${NC}"
            echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
            echo ""
            echo "To confirm, type the exact device path ('$DEST_DEV') below:"
            read -rp "Target confirmation: " FINAL_VERIFY

            if [[ "$FINAL_VERIFY" != "$DEST_DEV" ]]; then
                echo -e "${YELLOW}[!] Confirmation did not match. Aborting restore.${NC}"
                exit 1
            fi

            echo -e "${GREEN}[*] Uncompressing and writing to disk...${NC}"
            zstd -dc "$IMG_FILE" \
                | pv \
                | dd of="$DEST_DEV" bs=4M status=none conv=fsync

            sync
            echo -e "${GREEN}[✔] Restore complete! You can safely remove or reboot the media.${NC}"
            break
            ;;

        "Quit")
            echo "Exiting."
            exit 0
            ;;

        *)
            echo "Invalid option."
            ;;
    esac
done
