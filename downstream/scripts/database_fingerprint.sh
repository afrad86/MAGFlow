#!/usr/bin/env bash

# Return a stable, inexpensive fingerprint of a database path. File contents
# are not checksummed; canonical paths, relative names, sizes and mtimes are.
fingerprint_path() {
    local target="$1"
    local resolved
    resolved="$(readlink -f -- "${target}")"
    if [[ ! -e "${resolved}" ]]; then
        echo "ERROR: Fingerprint target does not exist: ${target}" >&2
        return 2
    fi
    {
        printf 'path\t%s\n' "${resolved}"
        if [[ -d "${resolved}" ]]; then
            find -L "${resolved}" -type f -printf '%P\t%s\t%T@\n' | LC_ALL=C sort
        else
            stat -c '%n\t%s\t%Y' "${resolved}"
        fi
    } | sha256sum | awk '{print $1}'
}
