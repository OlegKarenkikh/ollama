#!/bin/sh

set -eu

# Use plain progress output so build status is visible in CI logs by default.
BUILD_PROGRESS=${BUILD_PROGRESS:-plain}

. $(dirname $0)/env.sh

# Set PUSH to a non-empty string to trigger push instead of load
PUSH=${PUSH:-""}

if [ -z "${PUSH}" ] ; then
    echo "Building ${FINAL_IMAGE_REPO}:$VERSION locally.  set PUSH=1 to push"
    LOAD_OR_PUSH="--load"
else
    echo "Will be pushing ${FINAL_IMAGE_REPO}:$VERSION"
    LOAD_OR_PUSH="--push"
fi

build_image() {
    platform="$1"
    tag_suffix="$2"
    shift 2

    echo "==> Building ${FINAL_IMAGE_REPO}:${VERSION}${tag_suffix} for platform ${platform} (progress: ${BUILD_PROGRESS})"
    docker buildx build \
        ${LOAD_OR_PUSH} \
        --progress=${BUILD_PROGRESS} \
        --platform="${platform}" \
        ${OLLAMA_COMMON_BUILD_ARGS} \
        "$@" \
        -t ${FINAL_IMAGE_REPO}:${VERSION}${tag_suffix} \
        .
    echo "==> Completed ${FINAL_IMAGE_REPO}:${VERSION}${tag_suffix} for platform ${platform}"
}

build_image "${PLATFORM}" "" -f Dockerfile

if echo $PLATFORM | grep "amd64" > /dev/null; then
    build_image "linux/amd64" "-rocm" --build-arg FLAVOR=rocm -f Dockerfile
fi
