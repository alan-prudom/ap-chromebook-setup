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

# --- Detect Candidate USB Disks ---
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

# --- Pre-flight: ChromeOS USB Check ---
check_crostini_usb() {
    local candidates=($(get_usb_candidates))
    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo -e "${YELLOW}[!] Notice: No external USB storage block device detected.${NC}"
        echo -e "${YELLOW}    In ChromeOS / Crostini, USB drives must be passed to Linux:${NC}"
        echo -e "    1. Open ChromeOS Settings -> Advanced -> Developers -> Linux"
        echo -e "    2. Click 'Manage USB devices'"
        echo -e "    3. Toggle your USB drive switch to ON (share with Linux)\n"
    fi
}

# --- Test USB Accessibility ---
test_usb_device() {
    local dev="$1"
    assert_safe_target "$dev"

    echo ""
    echo -e "${BLUE}--- Testing Device: $dev ---${NC}"
    lsblk -o NAME,SIZE,TYPE,VENDOR,MODEL,LABEL,FSTYPE,MOUNTPOINTS "$dev"
    echo ""

    echo -n "[*] Testing read access (first 1MB)... "
    if dd if="$dev" of=/dev/null bs=1M count=1 status=none; then
        echo -e "${GREEN}PASS (Device is readable)${NC}"
    else
        echo -e "${RED}FAIL (Could not read from device)${NC}"
        return 1
    fi

    local dev_size_hr
    dev_size_hr=$(lsblk -dn -o SIZE "$dev" 2>/dev/null || true)
    echo -e "[*] Capacity: ${GREEN}$dev_size_hr${NC}"
    echo -e "${GREEN}[✔] $dev is ready for backup or restore.${NC}"
}

# --- Menu / Selection ---
ensure_deps
check_crostini_usb

while true; do
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}       Crostini Raw USB Disk Utility      ${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo "Available storage block devices & partitions:"
    echo ""
    lsblk -o NAME,SIZE,TYPE,VENDOR,MODEL,LABEL,MOUNTPOINTS,FSTYPE
    echo ""

    # Detect candidate USB disks
    candidates=($(get_usb_candidates))
    default_dev=""
    if [[ ${#candidates[@]} -eq 1 ]]; then
        default_dev="${candidates[0]}"
    fi

    PS3="Select an operation (1-4): "
    options=("Backup USB Drive to .img.zst" "Restore .img.zst to USB Drive" "Test USB Drive Accessibility" "Quit")
    select opt in "${options[@]}"; do
        case $opt in
            "Backup USB Drive to .img.zst")
                if [[ -n "$default_dev" ]]; then
                    read -rp "Enter source block device [$default_dev]: " SRC_DEV
                    SRC_DEV="${SRC_DEV:-$default_dev}"
                else
                    read -rp "Enter source block device (e.g., /dev/sda): " SRC_DEV
                fi
                assert_safe_target "$SRC_DEV"

                USER_HOME="${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}"
                USER_HOME="${USER_HOME:-$HOME}"
                DEFAULT_OUT="${USER_HOME}/usb_backup_$(date +%Y%m%d_%H%M%S).img.zst"
                read -rp "Destination file path [$DEFAULT_OUT]: " OUT_FILE
                OUT_FILE="${OUT_FILE:-$DEFAULT_OUT}"

                # Ensure destination directory exists and is writable
                DEST_DIR="$(dirname "$OUT_FILE")"
                mkdir -p "$DEST_DIR"

                DEV_SIZE=$(blockdev --getsize64 "$SRC_DEV")
                DEV_SIZE_HR=$(lsblk -dn -o SIZE "$SRC_DEV")

                # Disk space check on destination filesystem
                AVAIL_BYTES=$(df -B1 "$DEST_DIR" | awk 'NR==2 {print $4}')
                AVAIL_HR=$(df -h "$DEST_DIR" | awk 'NR==2 {print $4}')

                echo ""
                echo -e "${YELLOW}--- Backup Summary ---${NC}"
                echo -e "Source:            ${GREEN}$SRC_DEV${NC} ($DEV_SIZE_HR)"
                echo -e "Destination:       ${GREEN}$OUT_FILE${NC}"
                echo -e "Available space:   ${GREEN}$AVAIL_HR${NC}"

                if [[ "$AVAIL_BYTES" -lt "$DEV_SIZE" ]]; then
                    echo ""
                    echo -e "${YELLOW}[WARNING] Destination filesystem free space ($AVAIL_HR) is less than the raw device size ($DEV_SIZE_HR).${NC}"
                    echo -e "${YELLOW}          Compression with zstd will reduce image size, but if the disk holds uncompressible data,${NC}"
                    echo -e "${YELLOW}          the backup could run out of disk space mid-stream.${NC}"
                fi

                echo ""
                read -rp "Proceed with image creation? (y/N): " CONFIRM
                if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                    echo "Operation canceled."
                    break
                fi

                echo -e "${GREEN}[*] Imaging in progress... Press Ctrl+C to abort.${NC}"
                # Clean up partial output on failure/interruption
                trap 'rm -f "$OUT_FILE"; echo -e "\n${RED}[!] Backup aborted. Partial file removed.${NC}"; exit 1' INT TERM

                if dd if="$SRC_DEV" bs=4M status=none \
                    | pv -s "$DEV_SIZE" \
                    | zstd -T0 -3 > "$OUT_FILE"; then
                    trap - INT TERM
                    sync
                    echo ""
                    echo -e "${GREEN}===================================================================${NC}"
                    echo -e "${GREEN}                  🎉 Backup Successfully Created!                  ${NC}"
                    echo -e "${GREEN}===================================================================${NC}"
                    echo -e "[*] Generating SHA-256 checksum..."
                    sha256sum "$OUT_FILE" | tee "${OUT_FILE}.sha256"

                    # Set correct ownership if run via sudo
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
                else
                    trap - INT TERM
                    rm -f "$OUT_FILE"
                    echo -e "${RED}[ERROR] Backup failed. Partial file removed.${NC}"
                fi
                break
                ;;

            "Restore .img.zst to USB Drive")
                read -rp "Enter source .img.zst file path: " IMG_FILE
                if [[ ! -f "$IMG_FILE" ]]; then
                    echo -e "${RED}[ERROR] File '$IMG_FILE' does not exist.${NC}"
                    break
                fi

                # Optional checksum verification
                if [[ -f "${IMG_FILE}.sha256" ]]; then
                    echo -e "${YELLOW}[*] Checksum file found. Verifying archive integrity...${NC}"
                    if ! (cd "$(dirname "$IMG_FILE")" && sha256sum -c "$(basename "${IMG_FILE}.sha256")"); then
                        echo -e "${RED}[FATAL] Checksum verification failed! The image is corrupted.${NC}"
                        break
                    fi
                    echo -e "${GREEN}[✔] Image integrity verified.${NC}"
                fi

                if [[ -n "$default_dev" ]]; then
                    read -rp "Enter destination block device [$default_dev]: " DEST_DEV
                    DEST_DEV="${DEST_DEV:-$default_dev}"
                else
                    read -rp "Enter destination block device (e.g., /dev/sdb): " DEST_DEV
                fi
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
                    break
                fi

                echo -e "${GREEN}[*] Uncompressing and writing to disk...${NC}"
                zstd -dc "$IMG_FILE" \
                    | pv \
                    | dd of="$DEST_DEV" bs=4M status=none conv=fsync

                sync
                echo -e "${GREEN}[✔] Restore complete! You can safely remove or reboot the media.${NC}"
                break
                ;;

            "Test USB Drive Accessibility")
                if [[ -n "$default_dev" ]]; then
                    read -rp "Enter block device to test [$default_dev]: " TEST_DEV
                    TEST_DEV="${TEST_DEV:-$default_dev}"
                else
                    read -rp "Enter block device to test (e.g., /dev/sda): " TEST_DEV
                fi
                test_usb_device "$TEST_DEV" || true
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
    echo ""
    read -rp "Press Enter to return to main menu..." _dummy
    echo ""
done
