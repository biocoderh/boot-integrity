# boot-integrity

[![ShellCheck](https://github.com/biocoderh/boot-integrity/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/biocoderh/boot-integrity/actions/workflows/shellcheck.yml)

Systemd/Shell scripts to automate ESP cloning and clevis tpm2 pcr's changing on sysboot upgrades

## Scripts

- [install.sh](install.sh) - get, setup, clean.
- [update.sh](update.sh) - setup scripts to system.

- [boot-integrity.service](boot-integrity.service) - systemd start/stop service for main script.
- [boot-integrity.sh](boot-integrity.sh) - main script.

## Install

Requirements:
- curl
- git

- cryptsetup
- clevis, clevis-luks, clevis-pin-tpm2

```sh
/bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/biocoderh/boot-integrity/master/install.sh)"
```

## Configuration

All settings set throught environment variables.

**/etc/boot-integrity.env** file loads in script, key=value shell syntax

```env
EFI_MIRROR=/boot/efi2
CLEVIS_LUKS_SLOT=1
CLEVIS_LUKS_CONFIG='{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7,9"}'
CLEVIS_LUKS_UPGRADE_CONFIG='{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"0,1,2,3,4,5,7"}'
```

## Usage

```sh
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

```
## Links

[Safe automatic decryption of LUKS partition using TPM2](https://221b.uk/safe-automatic-decryption-luks-partition-tpm2)

[dracut-crypt-ssh](https://github.com/dracut-crypt-ssh/dracut-crypt-ssh)
