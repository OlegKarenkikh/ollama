#!/bin/sh
#
# Скрипт для сборки с push всех промежуточных слоев в Docker Hub
#

set -eu

SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/env.sh"

# Переопределяем для Docker Hub
DOCKER_ORG=${DOCKER_ORG:-"olegkarenkikh"}
FINAL_IMAGE_REPO=${FINAL_IMAGE_REPO:-"${DOCKER_ORG}/ollama"}
DOCKERFILE=${DOCKERFILE:-"Dockerfile"}
PLATFORM=${PLATFORM:-"linux/amd64"}
BUILD_PROGRESS=${BUILD_PROGRESS:-"plain"}
PARALLEL=${PARALLEL:-8}
VERSION=${VERSION:-$(git describe --tags --first-parent --abbrev=7 --long --dirty --always | sed -e "s/^v//g")}

# Cache для промежуточных слоев
CACHE_REPO="${FINAL_IMAGE_REPO}-cache"
CACHE_TAG="${VERSION}"

echo "=========================================="
echo "Building with intermediate layers push"
echo "=========================================="
echo "VERSION: ${VERSION}"
echo "PLATFORM: ${PLATFORM}"
echo "FINAL_IMAGE_REPO: ${FINAL_IMAGE_REPO}"
echo "CACHE_REPO: ${CACHE_REPO}"
echo "=========================================="

# Сборка с push промежуточных слоев и финального образа
sudo docker buildx build \
    --push \
    --progress="${BUILD_PROGRESS}" \
    --platform="${PLATFORM}" \
    --file="${DOCKERFILE}" \
    --tag="${FINAL_IMAGE_REPO}:${VERSION}" \
    --cache-to type=registry,ref=${CACHE_REPO}:${CACHE_TAG},mode=max \
    --cache-from type=registry,ref=${CACHE_REPO}:${CACHE_TAG} \
    ${OLLAMA_COMMON_BUILD_ARGS} \
    --build-arg PARALLEL="${PARALLEL}" \
    .

echo ""
echo "=========================================="
echo "Build completed!"
echo "Image: ${FINAL_IMAGE_REPO}:${VERSION}"
echo "Cache: ${CACHE_REPO}:${CACHE_TAG}"
echo "=========================================="
