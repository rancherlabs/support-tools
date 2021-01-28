#!/bin/bash
echo "Downloading kontainer-driver-metadata for v2.4"
wget --no-check-certificate -O v2-4.json https://releases.rancher.com/kontainer-driver-metadata/release-v2.4/data.json

echo "Downloading kontainer-driver-metadata for v2.5"
wget --no-check-certificate -O v2-5.json https://releases.rancher.com/kontainer-driver-metadata/release-v2.5/data.json
