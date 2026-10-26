#!/usr/bin/env bash
# Install the built package in a CLEAN container and check it.
#
#   tests/smoke.sh PACKAGE_FILE
#
# retrobox-core does not exist in any repository yet, so a stub package with
# that name satisfies the dependency; everything else (library packages,
# vlc-plugin-base, ...) must resolve from the distro's real repositories,
# which is what this test is for.
set -euo pipefail

PKG="$(realpath "${1:?usage: smoke.sh PACKAGE_FILE}")"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "${STUB_DIR}"' EXIT

fail() { echo "smoke.sh: FAIL: $*" >&2; exit 1; }

# --- the architecture of the package: file name and metadata -------------------
# MICROARCH (baseline | v3) tells which build this is.
MICROARCH="${MICROARCH:-baseline}"
case "${PKG}" in
    *.deb)
        host="$(dpkg --print-architecture)"
        label="${host}"
        [[ "${MICROARCH}" == v3 ]] && label="${host}v3"
        [[ "${PKG}" == *_"${label}".deb ]] || fail "the file name does not end in _${label}.deb"
        [[ "$(dpkg-deb -f "${PKG}" Architecture)" == "${host}" ]] || fail "Architecture is not ${host}"
        variant="$(dpkg-deb -f "${PKG}" Architecture-Variant)"
        if [[ "${MICROARCH}" == v3 ]]; then
            [[ "${variant}" == amd64v3 ]] || fail "Architecture-Variant is '${variant}', not amd64v3"
        else
            [[ -z "${variant}" ]] || fail "a baseline package must not have an Architecture-Variant"
        fi
        ;;
    *.rpm)
        label="$(uname -m)"
        [[ "${MICROARCH}" == v3 ]] && label="x86_64_v3"
        [[ "${PKG}" == *."${label}".rpm ]] || fail "the file name does not end in .${label}.rpm"
        [[ "$(rpm -qp --qf '%{ARCH}' "${PKG}")" == "${label}" ]] || fail "the rpm architecture is not ${label}"
        ;;
esac

case "${PKG}" in
    *.deb)
        export DEBIAN_FRONTEND=noninteractive
        mkdir -p "${STUB_DIR}/stub/DEBIAN"
        printf 'Package: retrobox-core\nVersion: 0\nArchitecture: all\nMaintainer: stub\nDescription: stub\n' \
            > "${STUB_DIR}/stub/DEBIAN/control"
        dpkg-deb --build "${STUB_DIR}/stub" "${STUB_DIR}/retrobox-core.deb" >/dev/null
        apt-get update
        apt-get install -y "${STUB_DIR}/retrobox-core.deb" "${PKG}"
        # Listed from the package file: container images exclude /usr/share/doc on install.
        FILES="$(dpkg-deb -c "${PKG}" | awk '{print $6}' | sed 's|^\./|/|; s|/$||')"
        ;;
    *.rpm)
        "$(dirname "${BASH_SOURCE[0]}")/../scripts/enable-rpmfusion.sh"
        dnf install -y rpm-build
        cat > "${STUB_DIR}/stub.spec" <<'SPEC'
Name: retrobox-core
Version: 0
Release: 1
Summary: stub
License: MIT
BuildArch: noarch
%description
stub
%files
SPEC
        rpmbuild -bb "${STUB_DIR}/stub.spec" --define "_topdir ${STUB_DIR}/rpmbuild" >/dev/null
        stub_rpm=("${STUB_DIR}"/rpmbuild/RPMS/noarch/retrobox-core-*.rpm)
        if ! dnf install -y "${stub_rpm[@]}" "${PKG}"; then
            # dnf may not install a package of a microarchitecture arch such as
            # x86_64_v3 yet (support is still arriving): install what it needs by
            # capability, then the package itself with rpm.
            echo "smoke.sh: dnf refused ${PKG##*/}; installing its dependencies and using rpm" >&2
            dnf install -y "${stub_rpm[@]}"
            mapfile -t caps < <(rpm -qpR "${PKG}" | grep -vE '^(rpmlib\(|retrobox-core)' | sort -u)
            dnf install -y "${caps[@]}"
            rpm -Uvh "${PKG}"
        fi
        FILES="$(rpm -qpl "${PKG}")"
        ;;
    *) fail "unsupported package type: ${PKG}" ;;
esac

BIN=/opt/retrobox/frontend/emulationstation
LINK=/usr/bin/retrobox-emulationstation

[[ -x "${BIN}" ]]  || fail "${BIN} missing or not executable"
[[ -L "${LINK}" ]] || fail "${LINK} is not a symlink"
[[ "$(readlink "${LINK}")" == "${BIN}" ]] || fail "${LINK} does not point to ${BIN}"
[[ -n "$(ls -A /opt/retrobox/frontend/resources 2>/dev/null)" ]] || fail "resources/ is empty"
[[ -n "$(find /opt/retrobox/frontend/locale -name '*.mo' 2>/dev/null | head -1)" ]] \
    || fail "no compiled translations in locale/"

# Licence notices must travel with the binary (checked in the package itself).
DOC=/usr/share/doc/retrobox-emulationstation
for f in copyright BUILDINFO licenses/MIT.txt licenses/batocera-emulationstation.LICENSE.md \
         licenses/OFL-1.1.txt licenses/Apache-2.0.txt licenses/nanosvg.NOTICE; do
    grep -qxF "${DOC}/${f}" <<<"${FILES}" || fail "${DOC}/${f} is not in the package"
done

# Nothing may be exposed to the desktop menu.
if grep -qE '\.desktop$|/usr/share/icons/' <<<"${FILES}"; then
    fail "the package must not ship a .desktop entry or icons"
fi

# Every shared library must resolve in a clean system.
if ldd "${BIN}" | grep -q 'not found'; then
    ldd "${BIN}" | grep 'not found' >&2
    fail "unresolved shared libraries"
fi

# It must start through $PATH (this exercises the /proc/self/exe patch: with
# a bare argv[0] upstream would look for resources in the wrong place).
( cd / && retrobox-emulationstation --help ) >/dev/null || fail "--help failed"

# ScreenScraper: its scraper is only in the binary when the developer login was
# compiled in. EXPECT_SCREENSCRAPER=1 (set by the workflow when the login secret
# exists) makes its absence a failure.
if grep -aq 'jeuInfos.php' "${BIN}"; then ss=yes; else ss=no; fi
echo "smoke.sh: ScreenScraper support in the binary: ${ss}"
if [[ "${EXPECT_SCREENSCRAPER:-0}" == 1 && "${ss}" != yes ]]; then
    fail "the ScreenScraper login was configured but the binary has no ScreenScraper support"
fi

echo "smoke.sh: OK (${PKG##*/})"
