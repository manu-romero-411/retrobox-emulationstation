#!/usr/bin/env bash
# Configure and build EmulationStation from a patched checkout.
#
#   scripts/build.sh SRC
#
# Desktop-Linux build: desktop OpenGL (no GLES), no CEC, system pugixml.
# The binary ends up in SRC/emulationstation (upstream's in-source layout).
#
# Environment: MICROARCH  baseline (default) or v3, see common.sh. Each level
#                         uses its own build directory, SRC/build-<MICROARCH>.
#
#   SCREENSCRAPER_DEV_LOGIN     "devid=<id>&devpassword=<password>", the developer
#                               login of ScreenScraper. EmulationStation only
#                               includes the ScreenScraper scraper when it is
#                               compiled in; without it the scraper is not in
#                               the menu at all.
#   SCREENSCRAPER_SOFTNAME      software name sent to ScreenScraper (default:
#                               Retrobox-Emulationstation); use the one the
#                               login was registered for.
# The login ends up in plain text inside the binary: see README.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: build.sh SRC}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"
BUILD="${SRC}/build-${MICROARCH}"

# cmake takes its initial CMAKE_C(XX)_FLAGS from these.
export CFLAGS="${CFLAGS:+${CFLAGS} }${MARCH_FLAGS}"
export CXXFLAGS="${CXXFLAGS:+${CXXFLAGS} }${MARCH_FLAGS}"

# --- ScreenScraper -------------------------------------------------------------
ss_args=()
if [[ -n "${SCREENSCRAPER_DEV_LOGIN:-}" ]]; then
    # Validate the shape without ever printing the value.
    if [[ ! "${SCREENSCRAPER_DEV_LOGIN}" =~ ^devid=[^\&]+\&devpassword=[^\&]+$ ]]; then
        echo "build.sh: SCREENSCRAPER_DEV_LOGIN must look like devid=<id>&devpassword=<password>" >&2
        exit 1
    fi
    ss_args=(
        "-DSCREENSCRAPER_DEV_LOGIN=${SCREENSCRAPER_DEV_LOGIN}"
        "-DSCREENSCRAPER_SOFTNAME=${SCREENSCRAPER_SOFTNAME:-Retrobox-Emulationstation}"
    )
    echo "build.sh: ScreenScraper support: ON (softname ${SCREENSCRAPER_SOFTNAME:-Retrobox-Emulationstation})"
else
    echo "build.sh: ScreenScraper support: OFF (SCREENSCRAPER_DEV_LOGIN is not set, so the scraper will not exist)" >&2
fi

cmake -S "${SRC}" -B "${BUILD}" -G Ninja \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBATOCERA=OFF -DCEC=OFF \
    -DGL=ON -DGLES=OFF -DGLES2=OFF -DGLES3=OFF \
    -DUSE_SYSTEM_PUGIXML=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    "${ss_args[@]}"
verify_march "${BUILD}/compile_commands.json"
cmake --build "${BUILD}" -j"$(nproc)"

[[ -x "${SRC}/emulationstation" ]] || { echo "build.sh: no emulationstation binary produced" >&2; exit 1; }
echo "build.sh: built ${SRC}/emulationstation"
