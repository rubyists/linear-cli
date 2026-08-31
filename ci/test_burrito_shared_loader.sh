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

private_runtime_for() {
    local user=$1
    local uid

    uid=$(id -u "$user") || return 1
    printf '/tmp/.burrito-musl-%s/ld-%s.so\n' "$uid" "${runtime_hash:0:32}"
}

assert_equal() {
    local actual=$1
    local expected=$2
    local description=$3

    if [ "$actual" != "$expected" ]; then
        printf '%s mismatch\nexpected: %s\nactual:   %s\n' \
            "$description" "$expected" "$actual" >&2
        return 1
    fi
}

assert_private_runtime() {
    local user=$1
    local expected_interpreter=$2
    local uid
    local erlexec
    local beam
    local erlexec_interpreter
    local beam_interpreter
    local runtime_dir_metadata
    local loader_metadata
    local loader_hash

    uid=$(id -u "$user") || return 1
    erlexec=$(find_erts_binary "$user" erlexec) || return 1
    beam=$(find_erts_binary "$user" beam.smp) || return 1

    if [ -z "$erlexec" ] || [ -z "$beam" ]; then
        printf 'Could not find both ERTS executables for %s\n' "$user" >&2
        return 1
    fi

    erlexec_interpreter=$(interpreter_for "$erlexec") || return 1
    beam_interpreter=$(interpreter_for "$beam") || return 1
    runtime_dir_metadata=$(sudo stat -c '%u:%a:%F' "$(dirname "$expected_interpreter")") || return 1
    loader_metadata=$(sudo stat -c '%u:%a:%F' "$expected_interpreter") || return 1
    loader_hash=$(sudo sha256sum "$expected_interpreter" | cut -d ' ' -f 1) || return 1

    assert_equal "$erlexec_interpreter" "$expected_interpreter" "erlexec interpreter" || return 1
    assert_equal "$beam_interpreter" "$expected_interpreter" "beam.smp interpreter" || return 1
    assert_equal "$runtime_dir_metadata" "$uid:700:directory" "private runtime directory metadata" || return 1
    assert_equal "$loader_metadata" "$uid:700:regular file" "private loader metadata" || return 1
    assert_equal "$loader_hash" "$runtime_hash" "private loader hash" || return 1
}

run_version "$user_a"
runtime_a=$(private_runtime_for "$user_a")
assert_private_runtime "$user_a" "$runtime_a"

# The UID-scoped path is short enough to fit the existing ELF interpreter
# segment, so its name is deterministic. An attacker may pre-position it, but
# ownership validation must fail closed without executing the attacker's file.
uid_b=$(id -u "$user_b")
attacker_runtime=$(private_runtime_for "$user_b")
attacker_runtime_dir=$(dirname "$attacker_runtime")
sudo -u "$user_a" mkdir -m 0755 -- "$attacker_runtime_dir"
sudo -u "$user_a" sh -c 'printf %s untrusted-private-loader > "$1"' sh "$attacker_runtime"

if run_version "$user_b" >"$test_root/prepositioned-private.log" 2>&1; then
    printf 'Burrito trusted an attacker-owned private runtime path\n' >&2
    exit 1
fi

grep -Fq UntrustedMuslRuntime "$test_root/prepositioned-private.log"
sudo rm -rf -- "$attacker_runtime_dir"

run_version "$user_b"
runtime_b=$(private_runtime_for "$user_b")
assert_private_runtime "$user_b" "$runtime_b"

# Prove the assertion helper itself cannot silently succeed after a failed
# check, including when called from an `if` condition where errexit is disabled.
sudo chmod 0701 "$runtime_b"
if assert_private_runtime "$user_b" "$runtime_b" >"$test_root/assertion-negative.log" 2>&1; then
    printf 'Private-runtime assertions accepted an invalid loader mode\n' >&2
    exit 1
fi
grep -Fq 'private loader metadata mismatch' "$test_root/assertion-negative.log"
sudo chmod 0700 "$runtime_b"
assert_private_runtime "$user_b" "$runtime_b"

if [ "$runtime_a" = "$runtime_b" ]; then
    printf 'Both users selected the same private runtime: %s\n' "$runtime_a" >&2
    exit 1
fi

legacy_contents=$(sudo cat "$legacy_loader")
legacy_metadata=$(sudo stat -c '%U:%a' "$legacy_loader")
assert_equal "$legacy_contents" untrusted-prepositioned-loader "legacy loader contents"
assert_equal "$legacy_metadata" "$user_a:754" "legacy loader metadata"

# A valid version/hash/path marker avoids reopening the full extracted release
# on every warm launch. An unreadable unrelated file proves the fast path is
# used; corrupting the marker must force a rescan and expose that read error.
erlexec_b=$(find_erts_binary "$user_b" erlexec)
erts_bin_dir=$(dirname "$erlexec_b")
erts_dir=$(dirname "$erts_bin_dir")
install_dir_b=$(dirname "$erts_dir")
marker_b="$install_dir_b/.burrito-musl-interpreters-v1"
marker_metadata=$(sudo stat -c '%u:%a:%F' "$marker_b")
marker_contents=$(sudo cat "$marker_b")
expected_marker=$(printf 'v1\n%s\n%s\n' "$runtime_hash" "$runtime_b")
assert_equal "$marker_metadata" "$uid_b:600:regular file" "interpreter marker metadata"
assert_equal "$marker_contents" "$expected_marker" "interpreter marker contents"

walk_sentinel="$install_dir_b/unreadable-walk-sentinel"
sudo -u "$user_b" touch "$walk_sentinel"
sudo -u "$user_b" chmod 000 "$walk_sentinel"
run_version "$user_b"

sudo -u "$user_b" sh -c 'printf %s corrupt-marker > "$1"' sh "$marker_b"
sudo -u "$user_b" chmod 0600 "$marker_b"

if run_version "$user_b" >"$test_root/invalid-marker.log" 2>&1; then
    printf 'Burrito trusted an invalid interpreter marker\n' >&2
    exit 1
fi
grep -Fq AccessDenied "$test_root/invalid-marker.log"

sudo rm -f -- "$walk_sentinel"
run_version "$user_b"
marker_contents=$(sudo cat "$marker_b")
assert_equal "$marker_contents" "$expected_marker" "repaired interpreter marker contents"
assert_private_runtime "$user_b" "$runtime_b"

# Replace the hostile object with the real loader bytes in the state left by
# an affected release: user A owns a valid shared loader at 0754. Reinstalling
# user B's payload must still ignore that object and choose user B's directory.
sudo rm -f -- "$legacy_loader"
sudo -u "$user_a" cp -- "$runtime_a" "$legacy_loader"
sudo -u "$user_a" chmod 0754 "$legacy_loader"
sudo rm -rf -- "$test_root/$user_b/data" "$(dirname "$runtime_b")"
run_version "$user_b"
runtime_b=$(private_runtime_for "$user_b")
assert_private_runtime "$user_b" "$runtime_b"
legacy_hash=$(sudo sha256sum "$legacy_loader" | cut -d ' ' -f 1)
legacy_metadata=$(sudo stat -c '%U:%a' "$legacy_loader")
assert_equal "$legacy_hash" "$runtime_hash" "stale legacy loader hash"
assert_equal "$legacy_metadata" "$user_a:754" "stale legacy loader metadata"

# `/tmp` can be cleared while Burrito's extracted release remains. The next
# launch must recreate and revalidate the private loader without re-extracting.
sudo rm -rf -- "$(dirname "$runtime_b")"
run_version "$user_b"
assert_private_runtime "$user_b" "$runtime_b"

printf 'Burrito shared-loader regression passed for %s and %s\n' "$user_a" "$user_b"
