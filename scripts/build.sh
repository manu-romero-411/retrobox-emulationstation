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

cmake -S "${SRC}" -B "${BUILD}" -G Ninja \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBATOCERA=OFF -DCEC=OFF \
    -DGL=ON -DGLES=OFF -DGLES2=OFF -DGLES3=OFF \
    -DUSE_SYSTEM_PUGIXML=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
verify_march "${BUILD}/compile_commands.json"
cmake --build "${BUILD}" -j"$(nproc)"

[[ -x "${SRC}/emulationstation" ]] || { echo "build.sh: no emulationstation binary produced" >&2; exit 1; }
echo "build.sh: built ${SRC}/emulationstation"
