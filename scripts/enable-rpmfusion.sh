#!/usr/bin/env bash
# Enable RPM Fusion (free) on Fedora: libvlc is not in the Fedora repos.
set -euo pipefail
if rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    exit 0
fi
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
