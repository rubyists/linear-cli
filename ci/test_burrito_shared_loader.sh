#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    printf 'usage: %s BURRITO_BINARY\n' "$0" >&2
    exit 64
fi

binary=$(realpath "$1")

if [ ! -x "$binary" ]; then
    printf 'Burrito binary is not executable: %s\n' "$binary" >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64)
        runtime_hash=71c35316aff45bbfd243d8eb9bfc4a58b6eb97cee09514cd2030e145b68107fb
        ;;
    aarch64)
        runtime_hash=6b558025200a5ed1308e2ce2675217afec71b6c5a9d561e52262ca948d59905e
        ;;
    *)
        printf 'Unsupported Linux architecture: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

sudo -n true

test_root=$(mktemp -d /tmp/lc-shared-loader-test.XXXXXX)
chmod 0711 "$test_root"
user_a="lcx17a$$"
user_b="lcx17b$$"
legacy_loader="/tmp/libc-musl-${runtime_hash}.so"
legacy_backup=""
private_runtime_dirs=()

cleanup() {
    sudo rm -f -- "$legacy_loader"

    for runtime_dir in "${private_runtime_dirs[@]}"; do
        sudo rm -rf -- "$runtime_dir"
    done

    if [ -n "$legacy_backup" ] && sudo test -e "$legacy_backup"; then
        sudo mv -- "$legacy_backup" "$legacy_loader"
    fi

    sudo userdel "$user_a" 2>/dev/null || true
    sudo userdel "$user_b" 2>/dev/null || true
    sudo rm -rf -- "$test_root"
}

trap cleanup EXIT

if sudo test -e "$legacy_loader"; then
    legacy_backup="$test_root/original-legacy-loader"
    sudo mv -- "$legacy_loader" "$legacy_backup"
fi

binary_copy="$test_root/lc"
sudo install -m 0755 -- "$binary" "$binary_copy"

for user in "$user_a" "$user_b"; do
    user_dir="$test_root/$user"
    sudo mkdir -- "$user_dir"
    sudo useradd --no-create-home --home-dir "$user_dir" --shell /bin/bash "$user"
    sudo chown "$user:$user" "$user_dir"
    private_runtime_dirs+=("/tmp/.burrito-musl-$(id -u "$user")")
done

# Recreate the affected-release state: user A owns a predictable shared
# loader at 0754, and the bytes are explicitly not Burrito's embedded loader.
sudo -u "$user_a" sh -c 'printf %s untrusted-prepositioned-loader > "$1"' sh "$legacy_loader"
sudo -u "$user_a" chmod 0754 "$legacy_loader"

run_version() {
    local user=$1
    local user_dir="$test_root/$user"

    sudo -H -u "$user" env \
        XDG_DATA_HOME="$user_dir/data" \
        "$binary_copy" version
}

find_erts_binary() {
    local user=$1
    local name=$2

    sudo find "$test_root/$user/data" -type f -path "*/erts-*/bin/$name" -print -quit
}

interpreter_for() {
    sudo readelf -l "$1" |
        sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p'
}

assert_private_runtime() {
    local user=$1
    local uid
    local erlexec
    local beam
    local erlexec_interpreter
    local beam_interpreter
    local expected_interpreter

    uid=$(id -u "$user")
    erlexec=$(find_erts_binary "$user" erlexec)
    beam=$(find_erts_binary "$user" beam.smp)
    erlexec_interpreter=$(interpreter_for "$erlexec")
    beam_interpreter=$(interpreter_for "$beam")
    expected_interpreter="/tmp/.burrito-musl-${uid}/ld-${runtime_hash:0:32}.so"

    test "$erlexec_interpreter" = "$expected_interpreter"
    test "$beam_interpreter" = "$expected_interpreter"
    test "$(sudo stat -c '%u:%a:%F' "$(dirname "$expected_interpreter")")" = "$uid:700:directory"
    test "$(sudo stat -c '%u:%a:%F' "$expected_interpreter")" = "$uid:700:regular file"
    test "$(sudo sha256sum "$expected_interpreter" | cut -d ' ' -f 1)" = "$runtime_hash"

    printf '%s\n' "$expected_interpreter"
}

run_version "$user_a"
runtime_a=$(assert_private_runtime "$user_a")

# The UID-scoped path is short enough to fit the existing ELF interpreter
# segment, so its name is deterministic. An attacker may pre-position it, but
# ownership validation must fail closed without executing the attacker's file.
uid_b=$(id -u "$user_b")
attacker_runtime_dir="/tmp/.burrito-musl-${uid_b}"
attacker_runtime="$attacker_runtime_dir/ld-${runtime_hash:0:32}.so"
sudo -u "$user_a" mkdir -m 0755 -- "$attacker_runtime_dir"
sudo -u "$user_a" sh -c 'printf %s untrusted-private-loader > "$1"' sh "$attacker_runtime"

if run_version "$user_b" >"$test_root/prepositioned-private.log" 2>&1; then
    printf 'Burrito trusted an attacker-owned private runtime path\n' >&2
    exit 1
fi

grep -Fq UntrustedMuslRuntime "$test_root/prepositioned-private.log"
sudo rm -rf -- "$attacker_runtime_dir"

run_version "$user_b"
runtime_b=$(assert_private_runtime "$user_b")

test "$runtime_a" != "$runtime_b"
test "$(sudo cat "$legacy_loader")" = untrusted-prepositioned-loader
test "$(sudo stat -c '%U:%a' "$legacy_loader")" = "$user_a:754"

# Replace the hostile object with the real loader bytes in the state left by
# an affected release: user A owns a valid shared loader at 0754. Reinstalling
# user B's payload must still ignore that object and choose user B's directory.
sudo rm -f -- "$legacy_loader"
sudo -u "$user_a" cp -- "$runtime_a" "$legacy_loader"
sudo -u "$user_a" chmod 0754 "$legacy_loader"
sudo rm -rf -- "$test_root/$user_b/data" "$(dirname "$runtime_b")"
run_version "$user_b"
runtime_b=$(assert_private_runtime "$user_b")
test "$(sudo sha256sum "$legacy_loader" | cut -d ' ' -f 1)" = "$runtime_hash"
test "$(sudo stat -c '%U:%a' "$legacy_loader")" = "$user_a:754"

# `/tmp` can be cleared while Burrito's extracted release remains. The next
# launch must recreate and revalidate the private loader without re-extracting.
sudo rm -rf -- "$(dirname "$runtime_b")"
run_version "$user_b"
test "$(assert_private_runtime "$user_b")" = "$runtime_b"

printf 'Burrito shared-loader regression passed for %s and %s\n' "$user_a" "$user_b"
