#!/usr/bin/env bash
# Build the .deb from a built checkout.
#
#   scripts/build-deb.sh SRC OUTDIR
#
# Environment: PKG_REVISION  package revision, bumped per build (default 1)
#
# Version:  <YYYYMMDD>.<HHMMSS>-<revision>~<distro tag>
#           (date and time of the upstream commit, UTC; its sha is in BUILDINFO)
# e.g.      20261013.143005-12~ubuntu24.04
# A Debian version cannot contain "_", so the YYYYMMDD_HHMMSS form used in
# release names is written with a dot here.
# The distro tag keeps the same revision from clashing between releases.
#
# Architecture, as the file name ends (MICROARCH=v3 only on amd64):
#   amd64 -> ..._amd64.deb      amd64, v3 -> ..._amd64v3.deb      arm64 -> ..._arm64.deb
# amd64v3 is an architecture *variant* (as in Ubuntu 25.10+): the control file
# says "Architecture: amd64" plus "Architecture-Variant: amd64v3", so dpkg on
# any release installs it as a normal amd64 package.
#
# Runtime dependencies on shared libraries are computed with
# dpkg-shlibdeps, so they match the library package names of the distro the
# package was built on (they differ between Debian and Ubuntu releases).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: build-deb.sh SRC OUTDIR}"
OUTDIR="${2:?usage: build-deb.sh SRC OUTDIR}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"
mkdir -p "${OUTDIR}"
OUTDIR="$(cd "${OUTDIR}" >/dev/null 2>&1 && pwd -P)"

es_snapshot "${SRC}"

# shellcheck disable=SC1091
. /etc/os-release
case "${ID}" in
    debian) TAG="deb${VERSION_ID}" ;;
    ubuntu) TAG="ubuntu${VERSION_ID}" ;;
    *)      TAG="${ID}${VERSION_ID}" ;;
esac
ARCH="$(dpkg --print-architecture)"
FILE_ARCH="${ARCH}"
if [[ "${MICROARCH}" == v3 ]]; then
    [[ "${ARCH}" == amd64 ]] || { echo "build-deb.sh: MICROARCH=v3 needs amd64, not ${ARCH}" >&2; exit 1; }
    FILE_ARCH="amd64v3"
fi
VERSION="${ES_DATE}.${ES_TIME}-${PKG_REVISION:-1}~${TAG}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
PKGDIR="${WORK}/${PKG_NAME}_${VERSION}_${FILE_ARCH}"

"${HERE}/stage.sh" "${SRC}" "${PKGDIR}"

# --- shared-library dependencies --------------------------------------------
mkdir -p "${WORK}/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "${PKG_NAME}" "${PKG_NAME}" \
    > "${WORK}/debian/control"
SHLIBS="$(cd "${WORK}" && dpkg-shlibdeps -O -e"${PKGDIR}${INSTALL_ROOT}/emulationstation" \
    | sed -n 's/^shlibs:Depends=//p')"
[[ -n "${SHLIBS}" ]] || { echo "build-deb.sh: dpkg-shlibdeps found no dependencies" >&2; exit 1; }

# retrobox-core: the `retrobox` launcher this frontend belongs to.
# vlc-plugin-base: libvlc loads its codecs/demuxers as plugins at run time,
# which no library dependency expresses.
DEPENDS="retrobox-core, vlc-plugin-base, ${SHLIBS}"

mkdir -p "${PKGDIR}/DEBIAN"
sed -e "s|@VERSION@|${VERSION}|g" -e "s|@ARCH@|${ARCH}|g" -e "s|@DEPENDS@|${DEPENDS}|g" \
    "${REPO_ROOT}/packaging/deb/control.in" > "${PKGDIR}/DEBIAN/control"
if [[ "${MICROARCH}" == v3 ]]; then
    sed -i '/^Architecture:/a Architecture-Variant: amd64v3' "${PKGDIR}/DEBIAN/control"
fi

OUT="${OUTDIR}/${PKG_NAME}_${VERSION}_${FILE_ARCH}.deb"
dpkg-deb --root-owner-group -Zxz --build "${PKGDIR}" "${OUT}"
echo "build-deb.sh: built ${OUT}"
echo "build-deb.sh: Depends: ${DEPENDS}"
