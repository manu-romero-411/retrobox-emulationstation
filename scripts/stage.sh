#!/usr/bin/env bash
# Lay out the installation tree of a built checkout into DESTDIR.
#
#   scripts/stage.sh SRC DESTDIR
#
# Layout (relative to DESTDIR):
#   /opt/retrobox/frontend/emulationstation   the binary
#   /opt/retrobox/frontend/resources/         fonts, images, default data
#   /opt/retrobox/frontend/locale/            translations (.mo)
#   /usr/bin/retrobox-emulationstation        symlink to the binary
#   /usr/share/doc/retrobox-emulationstation/copyright, licenses/, patches/,
#                                             BUILDINFO
#
# Format-agnostic: build-deb.sh and build-rpm.sh both use it. No .desktop
# entry and no icon on purpose: the frontend is launched through `retrobox`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: stage.sh SRC DESTDIR}"
DESTDIR="${2:?usage: stage.sh SRC DESTDIR}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"

# Refuse to package anything whose licence has not been reviewed.
"${HERE}/check-licenses.sh" "${SRC}"
es_snapshot "${SRC}"

if [[ -e "${DESTDIR}" ]] && [[ -n "$(ls -A "${DESTDIR}" 2>/dev/null)" ]]; then
    echo "stage.sh: ${DESTDIR} exists and is not empty" >&2
    exit 1
fi

ROOT="${DESTDIR}${INSTALL_ROOT}"
mkdir -p "${ROOT}"

install -m 755 "${SRC}/emulationstation" "${ROOT}/emulationstation"
strip --strip-unneeded "${ROOT}/emulationstation"

cp -a "${SRC}/resources" "${ROOT}/resources"
find "${ROOT}/resources" -type f \( -name '*.py' -o -name '*.sh' \) -delete

cp -a "${SRC}/locale" "${ROOT}/locale"
find "${ROOT}/locale" -type f \( -name '*.po' -o -name '*.pot' \
    -o -name 'CMakeLists.txt' -o -name '*.sh' \) -delete
find "${ROOT}/locale" -type d -empty -delete

# Modes: directories 755, everything else 644 (the binary stays 755).
find "${ROOT}" -type d -exec chmod 755 {} +
find "${ROOT}" -type f ! -path "${ROOT}/emulationstation" -exec chmod 644 {} +

mkdir -p "${DESTDIR}$(dirname "${BIN_LINK}")"
ln -s "${INSTALL_ROOT}/emulationstation" "${DESTDIR}${BIN_LINK}"

# --- licences ----------------------------------------------------------------
# MIT (and the other licences of upstream and its bundled components) require
# the notices to travel with the binary: `copyright` summarises, licenses/
# carries the verbatim texts.
DOC="${DESTDIR}/usr/share/doc/${PKG_NAME}"
LIC="${DOC}/licenses"
mkdir -p "${DOC}/patches" "${LIC}"

install -m 644 "${REPO_ROOT}/packaging/copyright" "${DOC}/copyright"
install -m 644 "${REPO_ROOT}"/licenses/*.txt "${LIC}/"
install -m 644 "${SRC}/LICENSE.md"                            "${LIC}/batocera-emulationstation.LICENSE.md"
install -m 644 "${SRC}/opensans_license.txt"                  "${LIC}/opensans_license.txt"
install -m 644 "${SRC}/ubuntu_licence.txt"                    "${LIC}/ubuntu_licence.txt"
install -m 644 "${SRC}/external/id3v2lib/LICENSE"             "${LIC}/id3v2lib.LICENSE"
install -m 644 "${SRC}/external/libcheevos/rcheevos/LICENSE"  "${LIC}/rcheevos.LICENSE"
# nanosvg keeps its licence in the header: copy the first comment block.
awk 'NR==1 && !/^\/\*/ {exit} {print} /\*\// {exit}' "${SRC}/external/nanosvg/nanosvg.h" \
    > "${LIC}/nanosvg.NOTICE"
[[ -s "${LIC}/nanosvg.NOTICE" ]] || { echo "stage.sh: could not extract the nanosvg notice" >&2; exit 1; }
chmod 644 "${LIC}/nanosvg.NOTICE"

# --- patches and build information --------------------------------------------
install -m 644 "${REPO_ROOT}"/patches/*.patch "${DOC}/patches/"
cat > "${DOC}/BUILDINFO" <<EOF2
upstream: ${UPSTREAM_URL}
commit:   ${ES_SHA_FULL}
date:     ${ES_STAMP} (UTC, commit date)
patches:  $(find "${REPO_ROOT}/patches" -name '*.patch' | wc -l)
EOF2
chmod 644 "${DOC}/BUILDINFO"

echo "stage.sh: staged ${INSTALL_ROOT} into ${DESTDIR}"
