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
here=$(cd "$(dirname "$me")" && pwd) || {
    printf "Could not determine script directory\n" >&2
    exit 98
}
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
default_image_name=$(printf "%s" "$base_dir" | tr '[:upper:]' '[:lower:]')
: "${BUILD_CONTEXT:=$(pwd)}"
: "${IMAGE_NAME:=$default_image_name}"
: "${LICENSE:=Proprietary/All Rights Reserved}"
: "${APP_VERSION:=$(< "$here"/../.version.txt)}"

usage() {
    cat <<-EOT
    Build a local container image

    Usage: $0 <options> <image_tag>
        Options:
            -c CONTAINERFILE  Path to the containerfile (default: first of ./Dockerfile, ./Containerfile, ./oci/Containerfile)
            -C CONTEXT        Build context (default: $BUILD_CONTEXT)
            -i NAME           Name of the image (default: $IMAGE_NAME)
            -l LICENSE        License of the image (default: $LICENSE)
            -h                Show help / usage
EOT
}

log() {
    printf "%s [%s] <%s> %s\n" "$(date '+%Y-%m-%d %H:%M:%S.%6N')" "$$" "${just_me:-$0}" "$*"
}

debug() {
    [ "$verbose" -lt 2 ] && return 0
    log "[DEBUG] $*" >&2
}

error() {
    log "[ERROR] $*" >&2
}

die() {
    local -i code
    code=$1
    shift
    error "$@"
    printf "\n" >&2
    usage >&2
    exit "$code"
}

verbose=0
while getopts :hvc:C:i:l: opt
do
    case $opt in
        c)
            CONTAINERFILE=$OPTARG
            ;;
        C)
            BUILD_CONTEXT=$OPTARG
            ;;
        i)
            IMAGE_NAME=$OPTARG
            ;;
        l)
            LICENSE=$OPTARG
            ;;
        v)
            verbose=$((verbose + 1))
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
[ -n "$tag" ] || die 1 "Missing image tag"
shift || true
[ "$#" -eq 0 ] || die 2 "Too many arguments"

if [ -z "${CONTAINERFILE:-}" ]
then
    for containerfile in Dockerfile Containerfile oci/Containerfile
    do
        if [ -f "$containerfile" ]
        then
            CONTAINERFILE=$containerfile
            break
        fi
    done
fi

[ -n "${CONTAINERFILE:-}" ] || die 3 "No containerfile found"
[ -f "$CONTAINERFILE" ] || die 4 "Containerfile '$CONTAINERFILE' not found"
[ -d "$BUILD_CONTEXT" ] || die 5 "Build context '$BUILD_CONTEXT' not found"

runtime=
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
then
    runtime=docker
elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1
then
    runtime=podman
else
    die 6 "No usable container runtime found"
fi

revision=$(git rev-parse HEAD) || die 7 "Could not determine git revision"
shortref=$(git rev-parse --short "$revision") || die 7 "Could not determine short git revision"
repo_url=$(git remote get-url origin) || die 7 "No remote found"
[ -n "$repo_url" ] || die 7 "No remote found"

if [[ $repo_url == *github.com/* ]]
then
    owner_and_repo=${repo_url#*github.com/}
else
    owner_and_repo=${repo_url##*:}
fi

service=$(basename "$owner_and_repo" .git)
# Rebuilt from owner_and_repo (path only), never $repo_url directly - a
# credential-bearing remote (https://TOKEN@github.com/...) would otherwise
# get baked verbatim into this label, and from there into any pushed image.
image_url="https://github.com/${owner_and_repo%.git}"
created=$(date --utc --iso-8601=seconds 2>/dev/null || gdate --utc --iso-8601=seconds) ||
    die 8 "Could not determine image creation timestamp"
full_tag=$IMAGE_NAME:$tag

debug "Building $full_tag with $runtime from $CONTAINERFILE"

"$runtime" build \
    --tag "$full_tag" \
    --label org.opencontainers.image.created="$created" \
    --label org.opencontainers.image.description="Image for $service" \
    --label org.opencontainers.image.licenses="$LICENSE" \
    --label org.opencontainers.image.revision="$revision" \
    --label org.opencontainers.image.url="$image_url" \
    --label org.opencontainers.image.title="$IMAGE_NAME" \
    --label org.opencontainers.image.source="$image_url/tree/$revision" \
    --label shortref="$shortref" \
    --build-arg APP_VERSION="$APP_VERSION" \
    -f "$CONTAINERFILE" \
    "$BUILD_CONTEXT"
