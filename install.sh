#!/usr/bin/env bash
# Downloads a precompiled Burrito release of `lc` for the current machine
# and installs it, plus the bin/ wrapper scripts (lcreate, lcls, lclose,
# lcomment, lproj) already bundled in the same release tarball, onto a
# directory already on $PATH. Fallback path for machines without
# Homebrew - see rubyists/homebrew-tap for that.
#
# LC_VERSION pins a specific release tag (e.g. "v1.0.0") instead of the
# latest one. LC_INSTALL_DIR pins a specific install directory instead of
# the first writable $PATH entry found.
#
# Records exactly what it installed and where in a manifest file, so
# uninstall.sh can remove precisely those files even if $PATH changes
# between install and uninstall.

repo=rubyists/linear-cli
version=${LC_VERSION:-latest}
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/linear-cli"
manifest="$state_dir/manifest"

detect_target() {
    case "$(uname -s)" in
        Darwin)
            case "$(uname -m)" in
                arm64) printf '%s\n' macos_aarch64 ;;
                *)
                    printf 'error: unsupported macOS architecture: %s (only aarch64 is built)\n' "$(uname -m)" >&2
                    exit 1
                    ;;
            esac
            ;;
        Linux)
            case "$(uname -m)" in
                x86_64) printf '%s\n' linux_x86_64 ;;
                aarch64) printf '%s\n' linux_aarch64 ;;
                *)
                    printf 'error: unsupported Linux architecture: %s (only x86_64 and aarch64 are built)\n' "$(uname -m)" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            printf 'error: unsupported OS: %s (use the container image on Windows)\n' "$(uname -s)" >&2
            exit 1
            ;;
    esac
}

# Prefer an install dir the user already has on $PATH (so no shell rc
# editing is required) over inventing a new one. $LC_INSTALL_DIR always
# wins if set, for anyone who wants a specific target.
pick_install_dir() {
    if [ -n "${LC_INSTALL_DIR:-}" ]
    then
        printf '%s\n' "$LC_INSTALL_DIR"
        return
    fi

    local dir
    IFS=: read -ra path_dirs <<< "$PATH"
    for dir in "${path_dirs[@]}"
    do
        if [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ]
        then
            printf '%s\n' "$dir"
            return
        fi
    done

    printf '%s\n' "$HOME/.local/bin"
}

# GNU coreutils' sha256sum vs. macOS's shasum -a 256 - both read the same
# "<hash>  <filename>" format via `-c -` on stdin.
checksum_cmd() {
    if command -v sha256sum >/dev/null 2>&1
    then
        printf 'sha256sum\n'
    elif command -v shasum >/dev/null 2>&1
    then
        printf 'shasum -a 256\n'
    else
        printf 'error: need sha256sum or shasum on $PATH to verify the download\n' >&2
        exit 1
    fi
}

release_url() {
    local asset="$1"
    if [ "$version" = "latest" ]
    then
        printf 'https://github.com/%s/releases/latest/download/%s\n' "$repo" "$asset"
    else
        printf 'https://github.com/%s/releases/download/%s/%s\n' "$repo" "$version" "$asset"
    fi
}

# Downloads lc_<target>.tar.gz + SHA256SUMS, verifies the tarball's
# checksum against just its own line (SHA256SUMS covers every target,
# not only the one being installed here), and extracts it. Prints the
# directory it extracted into.
fetch_lc() {
    local target="$1" tarball tmp_dir sum_tool
    tarball="lc_${target}.tar.gz"

    tmp_dir=$(mktemp -d) || {
        printf 'error: could not create a temp directory\n' >&2
        exit 1
    }
    trap 'rm -rf "$tmp_dir"' EXIT

    printf 'Downloading %s (%s)...\n' "$tarball" "$version" >&2

    # --retry-all-errors: GitHub's release-download redirect chain
    # occasionally drops the connection outright mid-stream (curl: (56)
    # Connection died) - verified directly, reproduced it repeatedly, and
    # confirmed plain --retry alone does NOT cover this specific error
    # (it's outside curl's default retriable set), only succeeding once
    # --retry-all-errors was added too.
    if ! curl -fsSL --retry 5 --retry-all-errors "$(release_url "$tarball")" -o "$tmp_dir/$tarball"
    then
        printf 'error: failed to download %s\n' "$tarball" >&2
        exit 1
    fi

    if ! curl -fsSL --retry 5 --retry-all-errors "$(release_url "SHA256SUMS")" -o "$tmp_dir/SHA256SUMS"
    then
        printf 'error: failed to download SHA256SUMS\n' >&2
        exit 1
    fi

    sum_tool=$(checksum_cmd)

    if ! grep -- " $tarball\$" "$tmp_dir/SHA256SUMS" | (cd "$tmp_dir" && $sum_tool -c -) >/dev/null
    then
        printf 'error: checksum verification failed for %s\n' "$tarball" >&2
        exit 1
    fi

    if ! tar -xzf "$tmp_dir/$tarball" -C "$tmp_dir"
    then
        printf 'error: failed to extract %s\n' "$tarball" >&2
        exit 1
    fi

    printf '%s\n' "$tmp_dir"
}

if ! command -v curl >/dev/null 2>&1
then
    printf 'error: curl is required\n' >&2
    exit 1
fi

target=$(detect_target) || exit 1
install_dir=$(pick_install_dir)
extracted_dir=$(fetch_lc "$target") || exit 1

if ! mkdir -p "$install_dir"
then
    printf 'error: could not create install dir %s\n' "$install_dir" >&2
    exit 1
fi

if ! mkdir -p "$state_dir"
then
    printf 'error: could not create state dir %s\n' "$state_dir" >&2
    exit 1
fi

: > "$manifest"
for name in lc lcreate lcls lclose lcomment lproj
do
    if ! install -m 755 "$extracted_dir/$name" "$install_dir/$name"
    then
        printf 'error: failed to install %s to %s\n' "$name" "$install_dir" >&2
        exit 1
    fi

    printf '%s\n' "$install_dir/$name" >> "$manifest"
done

# Gatekeeper blocks lc itself (a real Mach-O binary) on macOS since it
# isn't signed/notarized - the wrapper scripts are plain shell, so they're
# unaffected. Best-effort: xattr not existing/failing shouldn't fail the
# install, since the user can still do this by hand (see the README).
if [ "$(uname -s)" = Darwin ]
then
    xattr -d com.apple.quarantine "$install_dir/lc" 2>/dev/null || true
fi

printf 'Installed lc, lcreate, lcls, lclose, lcomment, lproj to %s\n' "$install_dir"
printf '(uninstall.sh will remove exactly these files - manifest at %s)\n' "$manifest"

case ":$PATH:" in
    *":$install_dir:"*) ;;
    *)
        printf '\n'
        printf 'warning: %s is not on your $PATH.\n' "$install_dir"
        printf 'Add it to your shell profile, e.g.:\n'
        printf '  export PATH="%s:$PATH"\n' "$install_dir"
        ;;
esac
