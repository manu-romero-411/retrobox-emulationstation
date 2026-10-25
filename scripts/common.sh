#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables are consumed by the scripts that source this file
# Shared settings for the packaging scripts. Meant to be sourced.

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/batocera-linux/batocera-emulationstation.git}"

PKG_NAME="retrobox-emulationstation"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/retrobox/frontend}"
BIN_LINK="${BIN_LINK:-/usr/bin/retrobox-emulationstation}"

# --- target -------------------------------------------------------------------
# MICROARCH selects the CPU level of the build:
#   baseline  the default of the distribution (x86-64 on amd64, armv8-a on arm64)
#   v3        x86-64-v3 (AVX2, BMI2, FMA, ...): Intel Haswell / AMD Excavator
#             (2013-2015) or newer. x86_64 only.
# The architecture name that goes at the end of the package file is the one
# each distribution family uses:
#   .deb  amd64 | amd64v3 | arm64          .rpm  x86_64 | x86_64_v3 | aarch64
MICROARCH="${MICROARCH:-baseline}"
HOST_CPU="$(uname -m)"
[[ "${HOST_CPU}" == arm64 ]] && HOST_CPU=aarch64
MARCH_FLAGS=""
case "${MICROARCH}" in
    baseline) ;;
    v3)
        if [[ "${HOST_CPU}" != x86_64 ]]; then
            echo "common.sh: MICROARCH=v3 only exists on x86_64 (this is ${HOST_CPU})" >&2
            exit 1
        fi
        MARCH_FLAGS="-march=x86-64-v3"
        ;;
    *)
        echo "common.sh: MICROARCH must be baseline or v3, not '${MICROARCH}'" >&2
        exit 1
        ;;
esac

# verify_march COMPILE_COMMANDS_JSON: every C/C++ unit must have been compiled
# with the flags of ${MICROARCH}: all of them with -march=x86-64-v3 for v3, none
# for baseline. (The ELF "ISA needed" note cannot prove it: it only reports v3
# when the code happens to use a v3-only instruction.)
verify_march() {
    python3 - "$1" "${MICROARCH}" <<'PYEOF2'
import json
import sys

path, microarch = sys.argv[1:3]
with open(path, encoding="utf-8") as handle:
    units = json.load(handle)
flag = "-march=x86-64-v3"
wrong, total = [], 0
for unit in units:
    if not unit["file"].endswith((".c", ".cc", ".cpp", ".cxx")):
        continue
    command = unit.get("command") or " ".join(unit.get("arguments", []))
    total += 1
    has = flag in command.split()
    if has != (microarch == "v3"):
        wrong.append(unit["file"])
if total == 0:
    sys.exit("verify_march: no C/C++ units found in " + path)
if wrong:
    sys.exit(f"verify_march: {len(wrong)} of {total} units were not built for "
             f"MICROARCH={microarch}, e.g. {wrong[0]}")
print(f"verify_march: all {total} units built for MICROARCH={microarch}")
PYEOF2
}

# Absolute path of the repository root.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"

# es_snapshot SRC: describes the upstream commit of a checkout made by
# fetch.sh. Sets, all in UTC and from the COMMIT date (not the build date, so
# rebuilding the same commit gives the same version):
#   ES_DATE  YYYYMMDD         ES_TIME  HHMMSS
#   ES_STAMP YYYYMMDD_HHMMSS  ES_SHA   7-char commit id
#   ES_SHA_FULL               full commit id
es_snapshot() {
    local src="$1" ct
    ct="$(git -C "${src}" log -1 --format=%ct)"
    ES_DATE="$(date -u -d "@${ct}" +%Y%m%d)"
    ES_TIME="$(date -u -d "@${ct}" +%H%M%S)"
    ES_STAMP="${ES_DATE}_${ES_TIME}"
    ES_SHA="$(git -C "${src}" rev-parse --short=7 HEAD)"
    ES_SHA_FULL="$(git -C "${src}" rev-parse HEAD)"
    SOURCE_DATE_EPOCH="${ct}"
    export ES_DATE ES_TIME ES_STAMP ES_SHA ES_SHA_FULL SOURCE_DATE_EPOCH
}
