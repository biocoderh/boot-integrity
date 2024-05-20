# boot-integrity

[![ShellCheck](https://github.com/biocoderh/boot-integrity/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/biocoderh/boot-integrity/actions/workflows/shellcheck.yml)

Systemd/Shell scripts to automate ESP cloning and clevis tpm2 pcr's changing on sysboot upgrades

Note: EFI partitions cloning done through dd if=(/boot/efi partition) of=(first ESP which not mounted to /boot/efi), it's also clone PARTLABEL and UUID which should not make issues, just leave one ESP on /etc/fstab.

## Install

Requirements:
- curl
- git

- cryptsetup
- clevis, clevis-luks, clevis-pin-tpm2
- tpm2-tools

```sh
/bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/biocoderh/boot-integrity/master/install.sh)"
```

## Scripts

- [install.sh](install.sh) - get, setup, clean.
- [update.sh](update.sh) - setup scripts to system.

- [boot-integrity.service](boot-integrity.service) - systemd start/stop service for main script.
- [boot-integrity.sh](boot-integrity.sh) - main script.

## Usage

```sh
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

```
## Links

[Safe automatic decryption of LUKS partition using TPM2](https://221b.uk/safe-automatic-decryption-luks-partition-tpm2)

[dracut-crypt-ssh](https://github.com/dracut-crypt-ssh/dracut-crypt-ssh)
