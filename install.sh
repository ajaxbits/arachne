#!/usr/bin/env bash
# A script to perform an initial install. Clone this repo onto the installer image and run it with sudo.

set -euxo pipefail

disko --arg hostName '"arachne"' --mode destroy,format,mount --flake .#arachne
mkdir -p /mnt/etc/ssh
cp /etc/ssh/ssh_host_ed25519_key /mnt/etc/ssh/ssh_host_ed25519_key
cp /etc/ssh/ssh_host_rsa_key /mnt/etc/ssh/ssh_host_rsa_key
nix build --accept-flake-config .#nixosConfigurations.arachne.config.system.build.toplevel
nixos-install --option require-sigs false --flake .#arachne
