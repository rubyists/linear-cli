#!/usr/bin/env bash

if readlink -f . >/dev/null 2>&1
then
    readlink_bin=readlink
elif greadlink -f . >/dev/null 2>&1
then
    readlink_bin=greadlink
else
    printf "You must install greadlink to use this (brew install coreutils)\n" >&2
    exit 97
fi

me=${BASH_SOURCE[0]}
if [ -L "$me" ]
then
    me=$($readlink_bin -f "$me") || {
        printf "Could not resolve script path\n" >&2
        exit 98
    }
fi
just_me=$(basename "$me")

repo_top=$(git rev-parse --show-toplevel) || {
    printf "Could not determine repository root\n" >&2
    exit 98
}
cd "$repo_top" || {
    printf "Could not cd to %s\n" "$repo_top" >&2
    exit 98
}

base_dir=$(basename "$(pwd)")
: "${IMAGE_NAME:=$base_dir}"

usage() {
    cat <<-EOT
    Save a local container image to a tar archive

    Usage: $0 <options> <image_tag> <output_tar>
        Options:
            -i NAME       Name of the image (default: $IMAGE_NAME)
            -h            Show help / usage
EOT
}

log() {
    printf "%s [%s] <%s> %s\n" "$(date '+%Y-%m-%d %H:%M:%S.%6N')" "$$" "${just_me:-$0}" "$*"
}

error() {
    log "[ERROR] $*" >&2
}

die() {
    local -i code
    code=$1
    shift
    error "$*"
    printf "\n" >&2
    usage >&2
    exit "$code"
}

while getopts :hi: opt
do
    case $opt in
        i)
            IMAGE_NAME=$OPTARG
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            die 28 "Option '$OPTARG' requires an argument"
            ;;
        ?)
            die 27 "Invalid option '$OPTARG'"
            ;;
    esac
done
shift $((OPTIND-1))

tag=${1:-}
output_tar=${2:-}
[ -n "$tag" ] || die 1 "Missing image tag"
[ -n "$output_tar" ] || die 2 "Missing output tar path"
shift 2 || true
[ "$#" -eq 0 ] || die 3 "Too many arguments"

if command -v docker >/dev/null 2>&1
then
    runtime=docker
elif command -v podman >/dev/null 2>&1
then
    runtime=podman
else
    die 4 "No container runtime found"
fi

image_ref="$IMAGE_NAME:$tag"
"$runtime" image inspect "$image_ref" >/dev/null 2>&1 || die 5 "Local image '$image_ref' not found"

mkdir -p "$(dirname "$output_tar")" || die 6 "Could not create output directory for '$output_tar'"
rm -f "$output_tar" || die 7 "Could not remove existing output file '$output_tar'"
"$runtime" save --output "$output_tar" "$image_ref" || die 8 "Could not save image '$image_ref'"
