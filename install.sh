#!/bin/sh -e

git clone https://github.com/biocoderh/boot-integrity.git
cd boot-integrity
chmod +x update.sh
./update.sh
cd ..
rm -rdf boot-integrity
