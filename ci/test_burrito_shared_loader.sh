#!/usr/bin/env bash

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

must() {
    if "$@"
    then
        return 0
    fi

    die "command failed: $*"
}

if [ "$#" -ne 1 ]
then
    printf 'usage: %s BURRITO_BINARY\n' "$0" >&2
    exit 64
fi

binary=$(realpath "$1") || die "unable to resolve Burrito binary: $1"

if [ ! -x "$binary" ]
then
    printf 'Burrito binary is not executable: %s\n' "$binary" >&2
    exit 1
fi

architecture=$(uname -m) || die "unable to determine architecture"

case "$architecture" in
    x86_64)
        runtime_hash=71c35316aff45bbfd243d8eb9bfc4a58b6eb97cee09514cd2030e145b68107fb
        ;;
    aarch64)
        runtime_hash=6b558025200a5ed1308e2ce2675217afec71b6c5a9d561e52262ca948d59905e
        ;;
    *)
        printf 'Unsupported Linux architecture: %s\n' "$architecture" >&2
        exit 1
        ;;
esac

if ! sudo -n true
then
    die "passwordless sudo is required for the shared-loader regression"
fi

test_root=$(mktemp -d /tmp/lc-shared-loader-test.XXXXXX) || die "unable to create temporary test directory"
must chmod 0711 "$test_root"
user_a="lcx17a$$"
user_b="lcx17b$$"
legacy_loader="/tmp/libc-musl-${runtime_hash}.so"
legacy_backup=""
private_runtime_dirs=()

cleanup() {
    if ! sudo rm -f -- "$legacy_loader"
    then
        printf 'WARNING: cleanup could not remove legacy loader: %s\n' "$legacy_loader" >&2
    fi

    for runtime_dir in "${private_runtime_dirs[@]}"
    do
        if ! sudo rm -rf -- "$runtime_dir"
        then
            printf 'WARNING: cleanup could not remove private runtime: %s\n' "$runtime_dir" >&2
        fi
    done

    if [ -n "$legacy_backup" ] && sudo test -e "$legacy_backup"
    then
        if ! sudo mv -- "$legacy_backup" "$legacy_loader"
        then
            printf 'WARNING: cleanup could not restore legacy loader: %s\n' "$legacy_loader" >&2
        fi
    fi

    if ! sudo userdel "$user_a" 2>/dev/null
    then
        :
    fi

    if ! sudo userdel "$user_b" 2>/dev/null
    then
        :
    fi

    if ! sudo rm -rf -- "$test_root"
    then
        printf 'WARNING: cleanup could not remove test directory: %s\n' "$test_root" >&2
    fi
}

trap cleanup EXIT

if sudo test -e "$legacy_loader"
then
    legacy_backup="$test_root/original-legacy-loader"
    must sudo mv -- "$legacy_loader" "$legacy_backup"
fi

binary_copy="$test_root/lc"
must sudo install -m 0755 -- "$binary" "$binary_copy"

for user in "$user_a" "$user_b"
do
    user_dir="$test_root/$user"
    must sudo mkdir -- "$user_dir"
    must sudo useradd --no-create-home --home-dir "$user_dir" --shell /bin/bash "$user"
    must sudo chown "$user:$user" "$user_dir"
    user_uid=$(id -u "$user") || die "unable to determine UID for $user"
    private_runtime_dirs+=("/tmp/.burrito-musl-$user_uid")
done

# Recreate the affected-release state: user A owns a predictable shared
# loader at 0754, and the bytes are explicitly not Burrito's embedded loader.
must sudo -u "$user_a" sh -c 'printf %s untrusted-prepositioned-loader > "$1"' sh "$legacy_loader"
must sudo -u "$user_a" chmod 0754 "$legacy_loader"

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
    program_headers=$(sudo readelf -l "$1") || return 1
    printf '%s\n' "$program_headers" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p'
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

    if [ "$actual" != "$expected" ]
    then
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

    if [ -z "$erlexec" ] || [ -z "$beam" ]
    then
        printf 'Could not find both ERTS executables for %s\n' "$user" >&2
        return 1
    fi

    erlexec_interpreter=$(interpreter_for "$erlexec") || return 1
    beam_interpreter=$(interpreter_for "$beam") || return 1
    runtime_dir_metadata=$(sudo stat -c '%u:%a:%F' "$(dirname "$expected_interpreter")") || return 1
    loader_metadata=$(sudo stat -c '%u:%a:%F' "$expected_interpreter") || return 1
    loader_checksum=$(sudo sha256sum "$expected_interpreter") || return 1
    loader_hash=${loader_checksum%% *}

    assert_equal "$erlexec_interpreter" "$expected_interpreter" "erlexec interpreter" || return 1
    assert_equal "$beam_interpreter" "$expected_interpreter" "beam.smp interpreter" || return 1
    assert_equal "$runtime_dir_metadata" "$uid:700:directory" "private runtime directory metadata" || return 1
    assert_equal "$loader_metadata" "$uid:700:regular file" "private loader metadata" || return 1
    assert_equal "$loader_hash" "$runtime_hash" "private loader hash" || return 1
}

must run_version "$user_a"
runtime_a=$(private_runtime_for "$user_a") || die "unable to determine private runtime for $user_a"
must assert_private_runtime "$user_a" "$runtime_a"

# The UID-scoped path is short enough to fit the existing ELF interpreter
# segment, so its name is deterministic. An attacker may pre-position it, but
# ownership validation must fail closed without executing the attacker's file.
uid_b=$(id -u "$user_b") || die "unable to determine UID for $user_b"
attacker_runtime=$(private_runtime_for "$user_b") || die "unable to determine private runtime for $user_b"
attacker_runtime_dir=$(dirname "$attacker_runtime") || die "unable to determine attacker runtime directory"
must sudo -u "$user_a" mkdir -m 0755 -- "$attacker_runtime_dir"
must sudo -u "$user_a" sh -c 'printf %s untrusted-private-loader > "$1"' sh "$attacker_runtime"

if run_version "$user_b" >"$test_root/prepositioned-private.log" 2>&1
then
    printf 'Burrito trusted an attacker-owned private runtime path\n' >&2
    exit 1
fi

if ! grep -Fq UntrustedMuslRuntime "$test_root/prepositioned-private.log"
then
    die "Burrito did not report the untrusted private runtime"
fi
must sudo rm -rf -- "$attacker_runtime_dir"

must run_version "$user_b"
runtime_b=$(private_runtime_for "$user_b") || die "unable to determine private runtime for $user_b"
must assert_private_runtime "$user_b" "$runtime_b"

# Prove the assertion helper itself cannot silently succeed after a failed
# check, including when called from an `if` condition where errexit is disabled.
must sudo chmod 0701 "$runtime_b"
if assert_private_runtime "$user_b" "$runtime_b" >"$test_root/assertion-negative.log" 2>&1
then
    printf 'Private-runtime assertions accepted an invalid loader mode\n' >&2
    exit 1
fi
if ! grep -Fq 'private loader metadata mismatch' "$test_root/assertion-negative.log"
then
    die "private-runtime assertion did not report the invalid loader mode"
fi
must sudo chmod 0700 "$runtime_b"
must assert_private_runtime "$user_b" "$runtime_b"

if [ "$runtime_a" = "$runtime_b" ]
then
    printf 'Both users selected the same private runtime: %s\n' "$runtime_a" >&2
    exit 1
fi

legacy_contents=$(sudo cat "$legacy_loader") || die "unable to read legacy loader"
legacy_metadata=$(sudo stat -c '%U:%a' "$legacy_loader") || die "unable to inspect legacy loader metadata"
must assert_equal "$legacy_contents" untrusted-prepositioned-loader "legacy loader contents"
must assert_equal "$legacy_metadata" "$user_a:754" "legacy loader metadata"

# A valid version/hash/path marker avoids reopening the full extracted release
# on every warm launch. An unreadable unrelated file proves the fast path is
# used; corrupting the marker must force a rescan and expose that read error.
erlexec_b=$(find_erts_binary "$user_b" erlexec) || die "unable to find erlexec for $user_b"
erts_bin_dir=$(dirname "$erlexec_b") || die "unable to resolve ERTS binary directory"
erts_dir=$(dirname "$erts_bin_dir") || die "unable to resolve ERTS directory"
install_dir_b=$(dirname "$erts_dir") || die "unable to resolve Burrito installation directory"
marker_b="$install_dir_b/.burrito-musl-interpreters-v1"
marker_metadata=$(sudo stat -c '%u:%a:%F' "$marker_b") || die "unable to inspect interpreter marker metadata"
marker_contents=$(sudo cat "$marker_b") || die "unable to read interpreter marker"
expected_marker=$(printf 'v1\n%s\n%s\n' "$runtime_hash" "$runtime_b")
must assert_equal "$marker_metadata" "$uid_b:600:regular file" "interpreter marker metadata"
must assert_equal "$marker_contents" "$expected_marker" "interpreter marker contents"

walk_sentinel="$install_dir_b/unreadable-walk-sentinel"
must sudo -u "$user_b" touch "$walk_sentinel"
must sudo -u "$user_b" chmod 000 "$walk_sentinel"
must run_version "$user_b"

must sudo -u "$user_b" sh -c 'printf %s corrupt-marker > "$1"' sh "$marker_b"
must sudo -u "$user_b" chmod 0600 "$marker_b"

if run_version "$user_b" >"$test_root/invalid-marker.log" 2>&1
then
    printf 'Burrito trusted an invalid interpreter marker\n' >&2
    exit 1
fi
if ! grep -Fq AccessDenied "$test_root/invalid-marker.log"
then
    die "Burrito did not report the corrupt interpreter marker"
fi

must sudo rm -f -- "$walk_sentinel"
must run_version "$user_b"
marker_contents=$(sudo cat "$marker_b") || die "unable to read repaired interpreter marker"
must assert_equal "$marker_contents" "$expected_marker" "repaired interpreter marker contents"
must assert_private_runtime "$user_b" "$runtime_b"

# Replace the hostile object with the real loader bytes in the state left by
# an affected release: user A owns a valid shared loader at 0754. Reinstalling
# user B's payload must still ignore that object and choose user B's directory.
must sudo rm -f -- "$legacy_loader"
must sudo -u "$user_a" cp -- "$runtime_a" "$legacy_loader"
must sudo -u "$user_a" chmod 0754 "$legacy_loader"
runtime_b_dir=$(dirname "$runtime_b") || die "unable to determine user B private runtime directory"
must sudo rm -rf -- "$test_root/$user_b/data" "$runtime_b_dir"
must run_version "$user_b"
runtime_b=$(private_runtime_for "$user_b") || die "unable to determine private runtime for $user_b"
must assert_private_runtime "$user_b" "$runtime_b"
legacy_checksum=$(sudo sha256sum "$legacy_loader") || die "unable to calculate legacy loader checksum"
legacy_hash=${legacy_checksum%% *}
legacy_metadata=$(sudo stat -c '%U:%a' "$legacy_loader") || die "unable to inspect legacy loader metadata"
must assert_equal "$legacy_hash" "$runtime_hash" "stale legacy loader hash"
must assert_equal "$legacy_metadata" "$user_a:754" "stale legacy loader metadata"

# `/tmp` can be cleared while Burrito's extracted release remains. The next
# launch must recreate and revalidate the private loader without re-extracting.
runtime_b_dir=$(dirname "$runtime_b") || die "unable to determine user B private runtime directory"
must sudo rm -rf -- "$runtime_b_dir"
must run_version "$user_b"
must assert_private_runtime "$user_b" "$runtime_b"

printf 'Burrito shared-loader regression passed for %s and %s\n' "$user_a" "$user_b"
