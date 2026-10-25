#!/usr/bin/env bash
# Fail if upstream carries third-party code or fonts that nobody has reviewed.
#
#   scripts/check-licenses.sh SRC
#
# It checks that:
#   * the licence files that stage.sh copies into the package exist;
#   * every directory in external/, every font in resources/ and every source
#     file with a "Copyright" line is listed in packaging/licenses-reviewed.txt.
#
# When it fails after an upstream update: read the licence of the new
# component, describe it in packaging/copyright, and list it in
# packaging/licenses-reviewed.txt. Set ALLOW_UNREVIEWED_LICENSES=1 to turn the
# failure into a warning (for a test build, never for a release).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: check-licenses.sh SRC}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"

problems=()

# Licence files stage.sh ships verbatim.
for file in LICENSE.md opensans_license.txt ubuntu_licence.txt \
            external/id3v2lib/LICENSE external/libcheevos/rcheevos/LICENSE \
            external/nanosvg/nanosvg.h; do
    [[ -f "${SRC}/${file}" ]] || problems+=("missing licence file: ${file}")
done

reviewed="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${REPO_ROOT}/packaging/licenses-reviewed.txt")"
is_reviewed() { grep -qxF "$1" <<<"${reviewed}"; }

# Bundled libraries.
if [[ -d "${SRC}/external" ]]; then
    while IFS= read -r -d '' dir; do
        rel="external/$(basename "${dir}")"
        # An empty directory (an uninitialised submodule) bundles nothing.
        [[ -n "$(find "${dir}" -type f -print -quit)" ]] || continue
        is_reviewed "${rel}" || problems+=("unreviewed bundled library: ${rel}")
    done < <(find "${SRC}/external" -mindepth 1 -maxdepth 1 -type d -print0)
fi

# Fonts.
while IFS= read -r -d '' font; do
    rel="${font#"${SRC}"/}"
    is_reviewed "${rel}" || problems+=("unreviewed font: ${rel}")
done < <(find "${SRC}/resources" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.woff' -o -name '*.woff2' \) -print0)

# Source files with a copyright notice (third-party code pasted into the tree).
while IFS= read -r -d '' file; do
    rel="${file#"${SRC}"/}"
    is_reviewed "${rel}" || problems+=("unreviewed source with a copyright notice: ${rel}")
done < <(grep -rIlZ 'Copyright' "${SRC}/es-core/src" "${SRC}/es-app/src" \
            --include='*.h' --include='*.hpp' --include='*.cpp' --include='*.c' || true)

if [[ ${#problems[@]} -gt 0 ]]; then
    printf 'check-licenses.sh: %s\n' "${problems[@]}" >&2
    echo "check-licenses.sh: review them, describe them in packaging/copyright and list them in packaging/licenses-reviewed.txt" >&2
    if [[ "${ALLOW_UNREVIEWED_LICENSES:-0}" == 1 ]]; then
        echo "check-licenses.sh: continuing because ALLOW_UNREVIEWED_LICENSES=1" >&2
        exit 0
    fi
    exit 1
fi
echo "check-licenses.sh: OK"
