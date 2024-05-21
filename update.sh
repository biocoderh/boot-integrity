#!/bin/sh -e

sudo cp boot-integrity.env /etc/boot-integrity.env

sudo cp -f boot-integrity.sh /usr/local/sbin/boot-integrity
sudo chmod +x /usr/local/sbin/boot-integrity

sudo cp -f boot-integrity.service /etc/systemd/system/boot-integrity.service
sudo systemctl daemon-reload
sudo systemctl enable --now boot-integrity.service
