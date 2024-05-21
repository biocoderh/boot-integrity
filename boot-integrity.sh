#!/bin/sh -e

EFI_MIRROR=${EFI_MIRROR:-/boot/efi2}
CLEVIS_LUKS_SLOT=${CLEVIS_LUKS_SLOT:-1}
DEFAULT_CLEVIS_LUKS_CONFIG='{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7,9"}'
DEFAULT_CLEVIS_LUKS_UPGRADE_CONFIG='{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7"}'

EFI_TS_FILE='/var/tmp/efi.modified.timestamp'
BOOT_TS_FILE='/var/tmp/boot.modified.timestamp'
TPM2_PCRREAD_FILE='/var/tmp/tpm2_pcrread.out'

set -o allexport
# shellcheck source=/dev/null
[ -f /etc/boot-integrity.env ] && . /etc/boot-integrity.env
set +o allexport

efi_sync() {
  [ -z "$EFI_MIRROR" ] && return

  DEV_EFI=$(findmnt -seno SOURCE /boot/efi ||:)
  DEV_EFI_MIRROR=$(findmnt -seno SOURCE "$EFI_MIRROR" ||:)

  [ -z "$DEV_EFI" ] && return
  [ -z "$DEV_EFI_MIRROR" ] && return

  EFI_SOURCE=$(findmnt -no SOURCE /boot/efi ||:)
  EFI_MIRROR_SOURCE=$(findmnt -no SOURCE "$EFI_MIRROR" ||:)

  [ -n "$EFI_SOURCE" ] && [ "$EFI_SOURCE" != "$DEV_EFI" ] && return
  [ -n "$EFI_MIRROR_SOURCE" ] && [ "$EFI_MIRROR_SOURCE" != "$DEV_EFI_MIRROR" ] && return

  [ -z "$EFI_SOURCE" ] && mount "$DEV_EFI" /boot/efi
  [ -z "$EFI_MIRROR_SOURCE" ] && mount "$DEV_EFI_MIRROR" "$EFI_MIRROR"

  echo "ESP Sync /boot/efi/ ($DEV_EFI) -> $EFI_MIRROR ($DEV_EFI_MIRROR)"
  rsync -a "/boot/efi/" "$EFI_MIRROR"

  [ -z "$EFI_SOURCE" ] && umount "$DEV_EFI"
  [ -z "$EFI_MIRROR_SOURCE" ] && umount "$DEV_EFI_MIRROR"
}

clevis_luks_regen_all() {
  for part in $(lsblk -o NAME -ln | grep -E '^[^loop]'); do
    if cryptsetup isLuks /dev/"$part"; then
      clevis luks regen -d /dev/"$part" -s "$CLEVIS_LUKS_SLOT"
    fi
  done

}

clevis_luks_edit_all() {
  for part in $(lsblk -o NAME -ln | grep -E '^[^loop]'); do
    if cryptsetup isLuks /dev/"$part"; then
      if clevis luks list -d /dev/"$part" tpm2 | grep -q "$1"; then
        echo "clevis luks config /dev/$part no changes"
      else
        echo "clevis luks config /dev/$part update: $1"
        clevis luks edit -d /dev/"$part" -s "$CLEVIS_LUKS_SLOT" -c "$1"
      fi
    fi
  done
}

status() {
  DEV_EFI=$(findmnt -seno SOURCE /boot/efi ||:)
  DEV_BOOT=$(findmnt -seno SOURCE /boot ||:)
  EFI_SOURCE=$(findmnt -no SOURCE /boot/efi ||:)
  BOOT_SOURCE=$(findmnt -no SOURCE /boot ||:)

  if [ -n "$DEV_EFI" ]; then
    if [ -n "$EFI_SOURCE" ] && [ "$EFI_SOURCE" != "$DEV_EFI" ]; then
      echo "ERROR: /boot/efi mounted to $EFI_SOURCE instead of $DEV_EFI"
      exit 1
    fi

    [ -z "$EFI_SOURCE" ] && mount "$DEV_EFI" /boot/efi
    EFI_TS=$(stat -c '%y' /boot/efi/EFI)
    [ -z "$EFI_SOURCE" ] && umount "$DEV_EFI"
    
    PREV_EFI_TS="no_data"
    [ -f "$EFI_TS_FILE" ] && PREV_EFI_TS=$(cat "$EFI_TS_FILE")
    
    if [ "$EFI_TS" != "$PREV_EFI_TS" ]; then
      echo "MODIFIED! EFI timestamp changed: $PREV_EFI_TS -> $EFI_TS"
      EFI_CHANGED='yes'
    else
      echo "OK! EFI no changes"
    fi
  fi

  if [ -n "$DEV_BOOT" ]; then
    if [ -n "$BOOT_SOURCE" ] && [ "$BOOT_SOURCE" != "$DEV_BOOT" ]; then
      echo "ERROR: /boot mounted to $BOOT_SOURCE instead of $DEV_BOOT"
      exit 1
    fi

    [ -z "$BOOT_SOURCE" ] && mount "$DEV_BOOT" /boot
    BOOT_TS=$(stat -c '%y' /boot)
    [ -f "$BOOT_TS_FILE" ] && PREV_BOOT_TS=$(cat "$BOOT_TS_FILE")
    [ -z "$BOOT_SOURCE" ] && umount "$DEV_BOOT"

    PREV_BOOT_TS="no_data"
    [ -f "$BOOT_TS_FILE" ] && PREV_BOOT_TS=$(cat "$BOOT_TS_FILE")

    if [ "$BOOT_TS" != "$PREV_BOOT_TS" ]; then
      echo "MODIFIED! BOOT timestamp changed: $PREV_BOOT_TS -> $BOOT_TS"
      BOOT_CHANGED='yes'
    else
      echo "OK! BOOT no changes"
    fi
  fi
}

case "$1" in
  efi-sync)
    efi_sync
    ;;
  clevis-luks-regen-all)
    clevis_luks_regen_all
    ;;
  clevis-luks-edit-all)
    clevis_luks_edit_all "$2"
    ;;
  tpm2-pcr-diff)
    if ! command -v tpm2_pcrread > /dev/null; then
      echo "tpm2-tools not installed"
      exit 1
    fi

    if [ -f "$TPM2_PCRREAD_FILE" ]; then
      tpm2_pcrread | diff "$TPM2_PCRREAD_FILE" -
    else
      echo "FILE_NOT_EXIST! TPM2-pcrread file not exist"
      tpm2_pcrread
    fi
    ;;
  status)
    status
    ;;
  start)
    clevis_luks_edit_all "${CLEVIS_LUKS_CONFIG:-$DEFAULT_CLEVIS_LUKS_CONFIG}"
    ;;
  stop)
    status
    
    [ "$EFI_CHANGED" = 'yes' ] && efi_sync

    if [ "$EFI_CHANGED" = 'yes' ] || [ "$BOOT_CHANGED" = 'yes' ]; then
      clevis_luks_edit_all "${CLEVIS_LUKS_UPGRADE_CONFIG:-$DEFAULT_CLEVIS_LUKS_UPGRADE_CONFIG}"
    fi

    [ -n "$EFI_TS" ] && echo "$EFI_TS" > "$EFI_TS_FILE"
    [ -n "$BOOT_TS" ] && echo "$BOOT_TS" > "$BOOT_TS_FILE"
    command -v tpm2_pcrread > /dev/null && tpm2_pcrread > "$TPM2_PCRREAD_FILE"
    ;;
  *)
cat << 'EOF'
Usage: boot-integrity <operation> [...]

<operation> is one of:
    efi-sync - sync EFI, /boot/efi -> $EFI_MIRROR, both ESP should persist in /etc/fstab 
    clevis-luks-regen-all - regen pins on all luks partitions, password promted
    clevis-luks-edit-all <config> - set config to all luks devices if changed
    tpm2-pcr-diff - diff TPM2 pcr pins from last boot    
    status - show EFI/BOOT status measured on FS modification time
    start - set default config to all devices if changed
    stop - if any changes run esp-sync and set clevis upgrade config

environment variables:
    EFI_MIRROR - ESP mirror mountpint, should be present in /etc/fstab: /etc/efi2
    CLEVIS_LUKS_SLOT - default clevis luks tpm2 slot: 1
    CLEVIS_LUKS_CONFIG - default clevis luks config: '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7,9"}'
    CLEVIS_LUKS_UPGRADE_CONFIG - upgrade clevis luks config: '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7"}'

EOF
  exit 1 ;;
esac
