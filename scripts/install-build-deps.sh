#!/usr/bin/env bash
# Install the build dependencies for the distro family we are running on.
#
#   scripts/install-build-deps.sh        (as root, inside a build container)
#
# Debian/Ubuntu: packaging/build-deps-deb.txt via apt.
# Fedora:        packaging/build-deps-rpm.txt via dnf, after enabling RPM
#                Fusion (free), which is where libvlc lives.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

# shellcheck disable=SC1091
. /etc/os-release

# read_list FILE: package names, comments and blank lines dropped.
read_list() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1"; }

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    mapfile -t pkgs < <(read_list "${REPO_ROOT}/packaging/build-deps-deb.txt")
    apt-get install -y --no-install-recommends "${pkgs[@]}"
elif command -v dnf >/dev/null 2>&1; then
    "${HERE}/enable-rpmfusion.sh"
    mapfile -t pkgs < <(read_list "${REPO_ROOT}/packaging/build-deps-rpm.txt")
    dnf install -y "${pkgs[@]}"
else
    echo "install-build-deps.sh: neither apt-get nor dnf found (${ID:-unknown})" >&2
    exit 1
fi
