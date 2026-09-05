#!/usr/bin/env bash

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || die "unable to resolve script directory"
repo_root=$(cd -- "$script_dir/.." && pwd) || die "unable to resolve repository root"
build_lib_dir=${1:-"$repo_root/app/_build/prod/lib"}

mdex_native_dir="$build_lib_dir/mdex_native/priv/native"
syntect_priv_dir="$build_lib_dir/makeup_syntect/priv"

# Mix links a dependency's priv directory back into deps/ by default. Replace
# that production-build symlink with a private copy before swapping NIFs, or a
# local release build would also replace the glibc NIF used by dev/test.
if [ -L "$syntect_priv_dir" ]
then
    syntect_priv_source=$(readlink -f -- "$syntect_priv_dir") || die "unable to resolve makeup_syntect priv symlink: $syntect_priv_dir"
    isolated_priv=$(mktemp -d "$build_lib_dir/makeup_syntect/.priv.XXXXXX") || die "unable to create isolated makeup_syntect priv directory"

    if ! cp -a "$syntect_priv_source/." "$isolated_priv/"
    then
        if ! rm -rf -- "$isolated_priv"
        then
            printf 'WARNING: unable to remove incomplete isolated priv directory: %s\n' "$isolated_priv" >&2
        fi
        die "unable to copy makeup_syntect priv directory: $syntect_priv_source"
    fi

    if ! unlink "$syntect_priv_dir"
    then
        if ! rm -rf -- "$isolated_priv"
        then
            printf 'WARNING: unable to remove isolated priv directory: %s\n' "$isolated_priv" >&2
        fi
        die "unable to remove production makeup_syntect priv symlink: $syntect_priv_dir"
    fi

    if ! mv "$isolated_priv" "$syntect_priv_dir"
    then
        if ! rm -rf -- "$isolated_priv"
        then
            printf 'WARNING: unable to remove isolated priv directory: %s\n' "$isolated_priv" >&2
        fi
        die "unable to install isolated makeup_syntect priv directory: $syntect_priv_dir"
    fi
fi

syntect_native_dir="$syntect_priv_dir/native"

for native_dir in "$mdex_native_dir" "$syntect_native_dir"
do
    if [ ! -d "$native_dir" ]
    then
        printf 'native directory does not exist: %s\n' "$native_dir" >&2
        exit 1
    fi
done

mdex_native_dir=$(cd -- "$mdex_native_dir" && pwd -P) || die "unable to resolve mdex_native directory"
syntect_native_dir=$(cd -- "$syntect_native_dir" && pwd -P) || die "unable to resolve makeup_syntect directory"

if ! shopt -s nullglob
then
    die "unable to enable nullglob"
fi
mdex_nifs=("$mdex_native_dir"/libmdex_native_nif-*-unknown-linux-musl.so)
syntect_host_nifs=("$syntect_native_dir"/libmakeup_syntect-*-unknown-linux-gnu.so)
if ! shopt -u nullglob
then
    die "unable to disable nullglob"
fi

if [ "${#mdex_nifs[@]}" -ne 1 ]
then
    printf 'expected exactly one mdex_native musl NIF in %s; found %d\n' \
        "$mdex_native_dir" "${#mdex_nifs[@]}" >&2
    exit 1
fi

if [ "${#syntect_host_nifs[@]}" -ne 1 ]
then
    printf 'expected exactly one makeup_syntect host NIF in %s; found %d\n' \
        "$syntect_native_dir" "${#syntect_host_nifs[@]}" >&2
    exit 1
fi

# makeup_syntect invokes its NIF while compiling its generated syntax-list
# documentation. Compiling it with TARGET_ABI=musl on an Ubuntu runner therefore
# fails before Mix can write a complete application. Compile it normally first,
# then replace the host NIF (at the path embedded in its BEAM module) with the
# checksummed musl release artifact.
syntect_host_nif=${syntect_host_nifs[0]}
syntect_host_name=$(basename -- "$syntect_host_nif") || die "unable to determine makeup_syntect NIF filename"
syntect_musl_name=${syntect_host_name/unknown-linux-gnu/unknown-linux-musl}
syntect_archive="$syntect_musl_name.tar.gz"

if [[ ! "$syntect_musl_name" =~ ^libmakeup_syntect-v([^-]+)- ]]
then
    printf 'could not determine makeup_syntect version from %s\n' "$syntect_host_name" >&2
    exit 1
fi

syntect_version=${BASH_REMATCH[1]}
checksum_file="$repo_root/app/deps/makeup_syntect/checksum-Elixir.MakeupSyntect.exs"

if [ ! -f "$checksum_file" ]
then
    printf 'makeup_syntect checksum file does not exist: %s\n' "$checksum_file" >&2
    exit 1
fi

if ! expected_checksum=$(
    elixir -e '
      [path, artifact] = System.argv()
      {checksums, _bindings} = Code.eval_file(path)
      IO.write(Map.fetch!(checksums, artifact))
    ' -- "$checksum_file" "$syntect_archive"
)
then
    die "unable to read checksum for $syntect_archive"
fi
expected_checksum=${expected_checksum#sha256:}

temp_dir=$(mktemp -d) || die "unable to create temporary directory"
cleanup() {
    if ! rm -rf -- "$temp_dir"
    then
        printf 'WARNING: unable to remove temporary directory: %s\n' "$temp_dir" >&2
    fi
}
trap cleanup EXIT

syntect_url="https://github.com/elixir-makeup/makeup_syntect/releases/download/v${syntect_version}/${syntect_archive}"
downloaded_archive="$temp_dir/$syntect_archive"

if ! curl --fail --location --silent --show-error --retry 3 \
    --output "$downloaded_archive" "$syntect_url"
then
    die "unable to download $syntect_url"
fi

checksum_output=$(sha256sum "$downloaded_archive") || die "unable to calculate checksum for $downloaded_archive"
actual_checksum=${checksum_output%% *}

if [ "$actual_checksum" != "$expected_checksum" ]
then
    printf 'checksum mismatch for %s\nexpected: %s\nactual:   %s\n' \
        "$syntect_archive" "$expected_checksum" "$actual_checksum" >&2
    exit 1
fi

if ! tar -xzf "$downloaded_archive" -C "$temp_dir"
then
    die "unable to extract $downloaded_archive"
fi
downloaded_nif="$temp_dir/$syntect_musl_name"

if [ ! -f "$downloaded_nif" ]
then
    printf 'makeup_syntect archive did not contain %s\n' "$syntect_musl_name" >&2
    exit 1
fi

if ! install -m 0755 "$downloaded_nif" "$syntect_host_nif"
then
    die "unable to install makeup_syntect musl NIF: $syntect_host_nif"
fi

# Rust's dynamically linked musl cdylibs depend on libgcc_s. Burrito starts
# its Linux ERTS with a musl loader but puts the host library directories on
# LD_LIBRARY_PATH, where Ubuntu's glibc libgcc_s may be found first. Give each
# NIF a uniquely named Alpine libgcc runtime beside it and patch DT_NEEDED and
# RUNPATH so the loader selects that copy deterministically.
if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1
then
    container_runtime=podman
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
then
    container_runtime=docker
else
    printf 'podman or docker is required to prepare the musl NIFs\n' >&2
    exit 1
fi

container_args=(run --rm)

if [ "$container_runtime" = podman ]
then
    container_args+=(--security-opt label=disable)
fi

container_args+=(
    -v "$mdex_native_dir:/mdex_native"
    -v "$syntect_native_dir:/makeup_syntect"
    -v "$repo_root/ci/patch_musl_nifs.sh:/patch_musl_nifs.sh:ro"
)

mdex_nif_name=$(basename -- "${mdex_nifs[0]}")

if ! "$container_runtime" "${container_args[@]}" alpine:3.22 sh /patch_musl_nifs.sh \
    "/mdex_native/$mdex_nif_name" libmdex_musl_libgcc_s.so.1 \
    "/makeup_syntect/$syntect_host_name" libmakeup_syntect_musl_libgcc_s.so.1
then
    die "unable to patch musl NIF dependencies"
fi

printf 'prepared musl NIF: %s\n' "${mdex_nifs[0]}"
printf 'prepared musl NIF: %s\n' "$syntect_host_nif"
