#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG=${IMAGE_TAG:-ollama:dev}
DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}
DOCKER_BUILD_ARGS=${DOCKER_BUILD_ARGS:-}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to build and run the container image." >&2
  exit 1
fi

echo "Building Ollama container image: ${IMAGE_TAG}" >&2
DOCKER_BUILDKIT=${DOCKER_BUILDKIT} docker build \
  -t "${IMAGE_TAG}" \
  -f Dockerfile \
  ${DOCKER_BUILD_ARGS} \
  .

echo "Running smoke test for ${IMAGE_TAG}" >&2
docker run --rm --entrypoint /usr/bin/ollama "${IMAGE_TAG}" --version

echo "Smoke test completed successfully." >&2
