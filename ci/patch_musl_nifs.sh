#!/bin/sh
# Runs inside Alpine to patch the supplied musl NIFs and bundle their libgcc
# runtimes. Arguments are alternating NIF paths and replacement libgcc names.

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

contains_line() {
    value=$1
    expected=$2

    if printf '%s\n' "$value" | grep -Fxq "$expected"
    then
        return 0
    fi

    return 1
}

if [ "$#" -eq 0 ]
then
    die "expected one or more NIF/libgcc-name pairs"
fi

apk add --no-cache libgcc patchelf || die "unable to install Alpine patching tools"

while [ "$#" -gt 0 ]
do
    nif=$1
    libgcc_name=$2
    shift 2

    bundled_libgcc="${nif%/*}/$libgcc_name"
    install -m 0755 /usr/lib/libgcc_s.so.1 "$bundled_libgcc" || die "unable to install libgcc for $nif"

    # libc.so is the musl dependency name; glibc NIFs require libc.so.6.
    # Check this before patching so a host artifact cannot slip through.
    needed=$(patchelf --print-needed "$nif") || die "unable to inspect dependencies for $nif"

    if ! contains_line "$needed" libc.so
    then
        die "musl NIF does not depend on libc.so: $nif"
    fi

    # Set RUNPATH before growing DT_NEEDED. With patchelf 0.18, doing these
    # two mutations in the opposite order can produce a loadable NIF that
    # crashes on its first call.
    patchelf --set-rpath '$ORIGIN' "$nif" || die "unable to set RUNPATH for $nif"
    needed=$(patchelf --print-needed "$nif") || die "unable to inspect libgcc dependency for $nif"

    if contains_line "$needed" libgcc_s.so.1
    then
        patchelf --replace-needed libgcc_s.so.1 "$libgcc_name" "$nif" || die "unable to replace libgcc dependency for $nif"
    elif ! contains_line "$needed" "$libgcc_name"
    then
        die "musl NIF has no expected libgcc dependency: $nif"
    fi

    needed=$(patchelf --print-needed "$nif") || die "unable to verify libgcc dependency for $nif"

    if ! contains_line "$needed" "$libgcc_name"
    then
        die "musl NIF did not retain renamed libgcc dependency: $nif"
    fi

    rpath=$(patchelf --print-rpath "$nif") || die "unable to inspect RUNPATH for $nif"

    if [ "$rpath" != '$ORIGIN' ]
    then
        die "musl NIF RUNPATH is not \$ORIGIN: $nif"
    fi
done
