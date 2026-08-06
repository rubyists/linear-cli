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
: "${IMAGE_NAME:=$base_dir}"
: "${REGISTRY:=ghcr.io}"
: "${REGISTRY_TOKEN:=${GITHUB_TOKEN:-}}"
: "${REGISTRY_USERNAME:=${GITHUB_ACTOR:-}}"

usage() {
    cat <<-EOT
    Publish a local image to a container registry

    Usage: $0 <options> <image_tag>
        Options:
            -i NAME       Name of the image (default: $IMAGE_NAME)
            -r REGISTRY   Registry to push to (default: $REGISTRY)
            -u USERNAME   Registry username (default: $REGISTRY_USERNAME)
            -b            Build the image before publishing
            -h            Show help / usage
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
    error "$*"
    printf "\n" >&2
    usage >&2
    exit "$code"
}

build_first=0
verbose=0
while getopts :hbvi:r:u: opt
do
    case $opt in
        b)
            build_first=1
            ;;
        i)
            IMAGE_NAME=$OPTARG
            ;;
        r)
            REGISTRY=$OPTARG
            ;;
        u)
            REGISTRY_USERNAME=$OPTARG
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

if command -v podman >/dev/null 2>&1
then
    runtime=podman
elif command -v docker >/dev/null 2>&1
then
    runtime=docker
else
    die 3 "No container runtime found"
fi

repo_url=$(git remote get-url origin) || die 4 "No remote found"
[ -n "$repo_url" ] || die 4 "No remote found"

if [[ $repo_url == *github.com/* ]]
then
    owner_and_repo=${repo_url#*github.com/}
else
    owner_and_repo=${repo_url##*:}
fi

owner=$(dirname "$owner_and_repo")
owner=${owner%.git}
image_repo="$REGISTRY/$owner/$IMAGE_NAME"
local_image="$IMAGE_NAME:$tag"

if [ "$build_first" -eq 1 ]
then
    debug "Building image $local_image before publish"
    IMAGE_NAME=$IMAGE_NAME "$here"/build_image.sh "$tag" ||
        die 7 "Failed to build local image '$local_image'"
fi

if ! "$runtime" image inspect "$local_image" >/dev/null 2>&1
then
    die 5 "Local image '$local_image' not found. Build it first or use -b"
fi

if [ -z "$REGISTRY_TOKEN" ]
then
    die 6 "No REGISTRY_TOKEN or GITHUB_TOKEN set, cannot login"
fi

if [ -z "$REGISTRY_USERNAME" ]
then
    REGISTRY_USERNAME=$(basename "$owner")
fi

debug "Logging into $REGISTRY as $REGISTRY_USERNAME"
if ! printf '%s' "$REGISTRY_TOKEN" | "$runtime" login -u "$REGISTRY_USERNAME" --password-stdin "$REGISTRY"
then
    die 8 "Failed to login to registry '$REGISTRY'"
fi

mapfile -t tags < <(echo "$tag" | awk -F'.' 'NF==3{print; print $1"."$2; print $1; next} NF==2{print; print $1; next} {print}')

for pushed_tag in "${tags[@]}"
do
    remote_image="$image_repo:$pushed_tag"
    debug "Pushing $local_image to $remote_image"
    "$runtime" tag "$local_image" "$remote_image" ||
        die 9 "Failed to tag '$local_image' as '$remote_image'"
    "$runtime" push "$remote_image" ||
        die 10 "Failed to push '$remote_image'"
done
