#!/bin/sh -e

esp_sync() {
  DEV_ESP=$(lsblk -nlsnpo NAME --filter 'PARTTYPENAME == "EFI System" && MOUNTPOINTS == "/boot/efi"' | head -n 1)
  DEV_ESP_CLONE=$(lsblk -nlsnpo NAME --filter 'PARTTYPENAME == "EFI System" && MOUNTPOINTS != "/boot/efi"' | head -n 1)

  if [ -n "$DEV_ESP" ] && [ -n "$DEV_ESP_CLONE" ]; then
    umount -q "$DEV_ESP" "$DEV_ESP_CLONE" || :
    if ! cmp "$DEV_ESP" "$DEV_ESP_CLONE"; then
      echo "ESP's differ, cloning $DEV_ESP -> $DEV_ESP_CLONE ..."
      dd if="$DEV_ESP" of="$DEV_ESP_CLONE"
    fi
    mount "$DEV_ESP" /boot/efi
  fi
}

clevis_luks_edit_all() {
  for part in $(lsblk -o NAME -ln | grep -E '^[^loop]'); do
    if cryptsetup isLuks /dev/"$part" 2> /dev/null; then
      if clevis luks list -d /dev/"$part" tpm2 | grep -q "$1"; then
        echo "clevis luks config /dev/$part no changes"
      else
        echo "clevis luks config /dev/$part update: $1"
        clevis luks edit -d /dev/"$part" -s 1 -c "$1"
      fi
    fi
  done
}

MD5SUM_EFI=""
MD5SUM_BOOT=""
MD5SUM_EFI_STATUS=""
MD5SUM_BOOT_STATUS=""
MD5SUM_EFI_FILE='/var/tmp/efi.md5sum'
MD5SUM_BOOT_FILE='/var/tmp/boot.md5sum'

checksum() {
  DEV_EFI=$(findmnt -n -o SOURCE --target /boot/efi)
  DEV_BOOT=$(findmnt -n -o SOURCE --target /boot)

  MD5SUM_EFI=$(md5sum "$DEV_EFI" | head -c 32)

  if [ -f "$MD5SUM_EFI_FILE" ]; then
    if grep -qxF "$MD5SUM_EFI" "$MD5SUM_EFI_FILE"; then
      echo "OK! EFI md5sum not changed: $MD5SUM_EFI"
      MD5SUM_EFI_STATUS="ok"
    else
      echo "MISSMATCH! EFI md5sum changed: $(cat $MD5SUM_EFI_FILE | head -c 32) -> $MD5SUM_EFI"
      MD5SUM_EFI_STATUS="missmatch"
    fi
  else
    echo "FILE_NOT_EXIST! EFI md5sum file not exist: $MD5SUM_EFI"
    MD5SUM_EFI_STATUS="file_not_exist"
  fi

  if [ "$DEV_EFI" = "$DEV_BOOT" ]; then
    echo "Warning: /boot/efi and /boot uses one partition $DEV_EFI"
    MD5SUM_BOOT="$MD5SUM_EFI"
    MD5SUM_BOOT_STATUS="$MD5SUM_EFI_STATUS"
    return
  else
    MD5SUM_BOOT=$(md5sum "$DEV_BOOT" | head -c 32)
  fi

  if [ -f "$MD5SUM_BOOT_FILE" ]; then
    if grep -qxF "$MD5SUM_BOOT" "$MD5SUM_BOOT_FILE"; then
      echo "OK! BOOT md5sum not changed: $MD5SUM_BOOT"
      MD5SUM_BOOT_STATUS="ok"
    else
      echo "MISSMATCH! BOOT md5sum changed: $(cat $MD5SUM_BOOT_FILE | head -c 32) -> $MD5SUM_BOOT"
      MD5SUM_BOOT_STATUS="missmatch"
    fi
  else
    echo "FILE_NOT_EXIST! BOOT md5sum file not exist: $MD5SUM_BOOT"
    MD5SUM_BOOT_STATUS="file_not_exist"
  fi
}

TPM2_PCRREAD_FILE='/var/tmp/tpm2_pcrread.out'

DEFAULT_CLEVIS_LUKS_CONFIG='{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7,9"}'
DEFAULT_CLEVIS_LUKS_UPGRADE_CONFIG='{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7"}'

case "$1" in
  esp-sync)
    esp_sync
    ;;
  clevis-luks-edit-all)
    clevis_luks_edit_all "$2"
    ;;
  checksum)
    checksum
    ;;
  tpm2-pcr-diff)
    if [ -f "$TPM2_PCRREAD_FILE" ]; then
      tpm2_pcrread | diff "$TPM2_PCRREAD_FILE" -
    else
      echo "FILE_NOT_EXIST! TPM2-pcrread file not exist"
      tpm2_pcrread
    fi
    ;;
  start)
    clevis_luks_edit_all "${CLEVIS_LUKS_CONFIG:-$DEFAULT_CLEVIS_LUKS_CONFIG}"
    ;;
  stop)
    checksum
    
    if [ "$MD5SUM_EFI_STATUS" != "ok" ]; then
      esp_sync
    fi

    if [ "$MD5SUM_EFI_STATUS" != "ok" ] || [ "$MD5SUM_BOOT_STATUS" != "ok" ]; then
      clevis_luks_edit_all "${CLEVIS_LUKS_UPGRADE_CONFIG:-$DEFAULT_CLEVIS_LUKS_UPGRADE_CONFIG}"
    fi

    echo "$MD5SUM_EFI" > "$MD5SUM_EFI_FILE"
    echo "$MD5SUM_BOOT" > "$MD5SUM_BOOT_FILE"
    tpm2_pcrread > "$TPM2_PCRREAD_FILE"
    ;;
  *)
cat << 'EOF'
Usage: boot-integrity <operation> [...]

<operation> is one of:
    esp-sync - sync two ESP partition if any changes, mounted one is source
    clevis-luks-edit-all <config> - set config to all luks devices if changed

    checksum - check md5sum EFI/BOOT partitions
    tpm2-pcr-diff - diff TPM2 pcr pins    

    start - set default config to all devices if changed
    stop - check /boot/efi and /boot partitions md5sum, if any changes do esp-sync and set upgrade clevis config to all luks partitions to complete efi/boot upgrade

environment veriables:
    CLEVIS_LUKS_CONFIG - default clevis luks config: '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7,9"}'
    CLEVIS_LUKS_UPGRADE_CONFIG - upgrade clevis luks config: '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7"}'

EOF
  exit 1 ;;
esac
