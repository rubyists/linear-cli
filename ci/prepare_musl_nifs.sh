#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
build_lib_dir=${1:-"$repo_root/app/_build/prod/lib"}

mdex_native_dir="$build_lib_dir/mdex_native/priv/native"
syntect_priv_dir="$build_lib_dir/makeup_syntect/priv"

# Mix links a dependency's priv directory back into deps/ by default. Replace
# that production-build symlink with a private copy before swapping NIFs, or a
# local release build would also replace the glibc NIF used by dev/test.
if [ -L "$syntect_priv_dir" ]; then
    syntect_priv_source=$(readlink -f -- "$syntect_priv_dir")
    isolated_priv=$(mktemp -d "$build_lib_dir/makeup_syntect/.priv.XXXXXX")

    if ! cp -a "$syntect_priv_source/." "$isolated_priv/"; then
        rm -rf -- "$isolated_priv"
        exit 1
    fi

    unlink "$syntect_priv_dir"
    mv "$isolated_priv" "$syntect_priv_dir"
fi

syntect_native_dir="$syntect_priv_dir/native"

for native_dir in "$mdex_native_dir" "$syntect_native_dir"; do
    if [ ! -d "$native_dir" ]; then
        printf 'native directory does not exist: %s\n' "$native_dir" >&2
        exit 1
    fi
done

mdex_native_dir=$(cd -- "$mdex_native_dir" && pwd -P)
syntect_native_dir=$(cd -- "$syntect_native_dir" && pwd -P)

shopt -s nullglob
mdex_nifs=("$mdex_native_dir"/libmdex_native_nif-*-unknown-linux-musl.so)
syntect_host_nifs=("$syntect_native_dir"/libmakeup_syntect-*-unknown-linux-gnu.so)
shopt -u nullglob

if [ "${#mdex_nifs[@]}" -ne 1 ]; then
    printf 'expected exactly one mdex_native musl NIF in %s; found %d\n' \
        "$mdex_native_dir" "${#mdex_nifs[@]}" >&2
    exit 1
fi

if [ "${#syntect_host_nifs[@]}" -ne 1 ]; then
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
syntect_host_name=$(basename -- "$syntect_host_nif")
syntect_musl_name=${syntect_host_name/unknown-linux-gnu/unknown-linux-musl}
syntect_archive="$syntect_musl_name.tar.gz"

if [[ ! "$syntect_musl_name" =~ ^libmakeup_syntect-v([^-]+)- ]]; then
    printf 'could not determine makeup_syntect version from %s\n' "$syntect_host_name" >&2
    exit 1
fi

syntect_version=${BASH_REMATCH[1]}
checksum_file="$repo_root/app/deps/makeup_syntect/checksum-Elixir.MakeupSyntect.exs"

if [ ! -f "$checksum_file" ]; then
    printf 'makeup_syntect checksum file does not exist: %s\n' "$checksum_file" >&2
    exit 1
fi

expected_checksum=$(
    elixir -e '
      [path, artifact] = System.argv()
      {checksums, _bindings} = Code.eval_file(path)
      IO.write(Map.fetch!(checksums, artifact))
    ' -- "$checksum_file" "$syntect_archive"
)
expected_checksum=${expected_checksum#sha256:}

temp_dir=$(mktemp -d)
cleanup() {
    rm -rf -- "$temp_dir"
}
trap cleanup EXIT

syntect_url="https://github.com/elixir-makeup/makeup_syntect/releases/download/v${syntect_version}/${syntect_archive}"
downloaded_archive="$temp_dir/$syntect_archive"

curl --fail --location --silent --show-error --retry 3 \
    --output "$downloaded_archive" "$syntect_url"

actual_checksum=$(sha256sum "$downloaded_archive" | cut -d ' ' -f 1)

if [ "$actual_checksum" != "$expected_checksum" ]; then
    printf 'checksum mismatch for %s\nexpected: %s\nactual:   %s\n' \
        "$syntect_archive" "$expected_checksum" "$actual_checksum" >&2
    exit 1
fi

tar -xzf "$downloaded_archive" -C "$temp_dir"
downloaded_nif="$temp_dir/$syntect_musl_name"

if [ ! -f "$downloaded_nif" ]; then
    printf 'makeup_syntect archive did not contain %s\n' "$syntect_musl_name" >&2
    exit 1
fi

install -m 0755 "$downloaded_nif" "$syntect_host_nif"

# Rust's dynamically linked musl cdylibs depend on libgcc_s. Burrito starts
# its Linux ERTS with a musl loader but puts the host library directories on
# LD_LIBRARY_PATH, where Ubuntu's glibc libgcc_s may be found first. Give each
# NIF a uniquely named Alpine libgcc runtime beside it and patch DT_NEEDED and
# RUNPATH so the loader selects that copy deterministically.
if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    container_runtime=podman
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    container_runtime=docker
else
    printf 'podman or docker is required to prepare the musl NIFs\n' >&2
    exit 1
fi

container_args=(run --rm)

if [ "$container_runtime" = podman ]; then
    container_args+=(--security-opt label=disable)
fi

container_args+=(
    -v "$mdex_native_dir:/mdex_native"
    -v "$syntect_native_dir:/makeup_syntect"
)

mdex_nif_name=$(basename -- "${mdex_nifs[0]}")

# The single-quoted body is intentionally expanded by the container's shell.
# shellcheck disable=SC2016
"$container_runtime" "${container_args[@]}" alpine:3.22 sh -euxc '
    apk add --no-cache libgcc patchelf

    while [ "$#" -gt 0 ]; do
        nif="$1"
        libgcc_name="$2"
        shift 2

        bundled_libgcc="${nif%/*}/$libgcc_name"
        install -m 0755 /usr/lib/libgcc_s.so.1 "$bundled_libgcc"

        # libc.so is the musl dependency name; glibc NIFs require libc.so.6.
        # Check this before patching so a host artifact cannot slip through.
        patchelf --print-needed "$nif" | grep -Fxq libc.so

        # Set RUNPATH before growing DT_NEEDED. With patchelf 0.18, doing these
        # two mutations in the opposite order can produce a loadable NIF that
        # crashes on its first call.
        patchelf --set-rpath "\$ORIGIN" "$nif"

        if patchelf --print-needed "$nif" | grep -Fxq libgcc_s.so.1; then
            patchelf --replace-needed libgcc_s.so.1 "$libgcc_name" "$nif"
        elif ! patchelf --print-needed "$nif" | grep -Fxq "$libgcc_name"; then
            printf "musl NIF has no expected libgcc dependency: %s\n" "$nif" >&2
            exit 1
        fi

        patchelf --print-needed "$nif" | grep -Fxq "$libgcc_name"
        test "$(patchelf --print-rpath "$nif")" = "\$ORIGIN"
    done
' sh \
    "/mdex_native/$mdex_nif_name" libmdex_musl_libgcc_s.so.1 \
    "/makeup_syntect/$syntect_host_name" libmakeup_syntect_musl_libgcc_s.so.1

printf 'prepared musl NIF: %s\n' "${mdex_nifs[0]}"
printf 'prepared musl NIF: %s\n' "$syntect_host_nif"
