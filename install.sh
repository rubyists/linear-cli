#!/usr/bin/env bash
# Builds a native Burrito release of `lc` for the current machine and
# installs it, plus the bin/ wrapper scripts (lcreate, lcls, lclose,
# lcomment, lproj), onto a directory already on $PATH. Fallback path for
# machines without Homebrew - see rubyists/homebrew-tap once it exists.
#
# Records exactly what it installed and where in a manifest file, so
# uninstall.sh can remove precisely those files even if $PATH changes
# between install and uninstall.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$repo_root/app"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/linear-cli-ex"
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
                *)
                    printf 'error: unsupported Linux architecture: %s (only x86_64 is built)\n' "$(uname -m)" >&2
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

build_lc() {
    local target="$1"

    if ! cd "$app_dir"
    then
        printf 'error: could not cd into %s\n' "$app_dir" >&2
        exit 1
    fi

    rm -rf _build/prod

    have_mise=0
    if command -v mise >/dev/null 2>&1
    then
        have_mise=1
    else
        printf 'warning: mise not found on PATH; building with whatever Erlang/Elixir are active\n' >&2
    fi

    if [ "$have_mise" -eq 1 ]
    then
        MIX_ENV=prod BURRITO_TARGET="$target" mise exec -- mix release lc --overwrite
    else
        MIX_ENV=prod BURRITO_TARGET="$target" mix release lc --overwrite
    fi

    if [ "$?" -ne 0 ]
    then
        printf 'error: build failed (mix release lc, target %s)\n' "$target" >&2
        exit 1
    fi
}

target=$(detect_target) || exit 1
install_dir=$(pick_install_dir)

printf 'Building lc (%s)...\n' "$target"
build_lc "$target"

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
    src="$app_dir/burrito_out/lc_${target}"
    [ "$name" = lc ] || src="$repo_root/bin/$name"

    if ! install -m 755 "$src" "$install_dir/$name"
    then
        printf 'error: failed to install %s to %s\n' "$name" "$install_dir" >&2
        exit 1
    fi

    printf '%s\n' "$install_dir/$name" >> "$manifest"
done

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
