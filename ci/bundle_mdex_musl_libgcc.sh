#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
native_dir=${1:-"$repo_root/app/_build/prod/lib/mdex_native/priv/native"}

if [ ! -d "$native_dir" ]; then
    printf 'mdex_native directory does not exist: %s\n' "$native_dir" >&2
    exit 1
fi

native_dir=$(cd -- "$native_dir" && pwd)
shopt -s nullglob
musl_nifs=("$native_dir"/libmdex_native_nif-*-unknown-linux-musl.so)
shopt -u nullglob

if [ "${#musl_nifs[@]}" -ne 1 ]; then
    printf 'expected exactly one mdex_native musl NIF in %s; found %d\n' \
        "$native_dir" "${#musl_nifs[@]}" >&2
    exit 1
fi

# Rust's dynamically linked musl cdylibs depend on libgcc_s. Burrito starts
# its Linux ERTS with a musl loader but puts the host library directories on
# LD_LIBRARY_PATH, where a glibc libgcc_s may be found first. Give Alpine's
# musl-compatible runtime a unique dependency name and keep it beside the NIF
# so the loader cannot accidentally select the host copy.
nif_name=$(basename -- "${musl_nifs[0]}")
libgcc_name=libmdex_musl_libgcc_s.so.1

if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    container_runtime=podman
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    container_runtime=docker
else
    printf 'podman or docker is required to bundle the musl libgcc runtime\n' >&2
    exit 1
fi

container_args=(run --rm)

if [ "$container_runtime" = podman ]; then
    container_args+=(--security-opt label=disable)
fi

container_args+=(-v "$native_dir:/native")

# The single-quoted body is intentionally expanded by the container's shell.
# shellcheck disable=SC2016
"$container_runtime" "${container_args[@]}" alpine:3.22 sh -euxc '
    apk add --no-cache libgcc patchelf

    nif="/native/$1"
    bundled_libgcc="/native/$2"
    install -m 0755 /usr/lib/libgcc_s.so.1 "$bundled_libgcc"

    # Set RUNPATH before growing DT_NEEDED. With patchelf 0.18, doing these
    # two mutations in the opposite order can produce a loadable NIF that
    # crashes on its first call.
    patchelf --set-rpath "\$ORIGIN" "$nif"

    if patchelf --print-needed "$nif" | grep -Fxq libgcc_s.so.1; then
        patchelf --replace-needed libgcc_s.so.1 "$2" "$nif"
    elif ! patchelf --print-needed "$nif" | grep -Fxq "$2"; then
        printf "mdex_native NIF has no expected libgcc dependency: %s\\n" "$nif" >&2
        exit 1
    fi

    patchelf --print-needed "$nif" | grep -Fxq "$2"
    test "$(patchelf --print-rpath "$nif")" = "\$ORIGIN"
' sh "$nif_name" "$libgcc_name"

printf 'bundled musl libgcc runtime for %s\n' "${musl_nifs[0]}"
