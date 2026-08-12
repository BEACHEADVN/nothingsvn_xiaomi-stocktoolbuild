#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
set -e

export DEBIAN_FRONTEND=noninteractive

# Check for root/sudo access
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root (or with sudo)"
    exit 1
fi

echo "[INFO] Removing Firefox..."
apt purge -y firefox 2>/dev/null || true

echo "[INFO] Updating package lists..."
apt update -y && apt upgrade -y

echo "[INFO] Installing software-properties-common..."
apt install -y software-properties-common

echo "[INFO] Adding ubuntu-toolchain-r PPA..."
add-apt-repository -y ppa:ubuntu-toolchain-r/test

echo "[INFO] Updating package lists again..."
apt update -y

echo "[INFO] Installing required packages..."
apt install -y \
    aria2 jq rclone sshpass python-is-python3 wget python3 lz4 \
    xz-utils device-tree-compiler zlib1g-dev gcc g++ libc6 libstdc++6 \
    python3-pip dialog libgtk-3-dev aapt busybox zip erofs-utils unzip \
    p7zip-full zipalign zstd bc android-sdk-libsparse-utils xmlstarlet

echo "[INFO] Installing Python dependencies..."
pip3 install --no-cache-dir ConfigObj telebot setuptools

echo "[INFO] Cleaning up..."
apt clean && rm -rf /var/lib/apt/lists/*

echo "[INFO] Setup completed successfully!"