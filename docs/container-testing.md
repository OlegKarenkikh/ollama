# Container-based build and smoke test

Use this guide to build the Ollama container image locally and run a quick smoke test to ensure the binary launches correctly. The steps rely on Docker with BuildKit enabled.

## Prerequisites

- Docker 24 or later with BuildKit support
- Access to the project root (the directory containing `Dockerfile`)

## Quick start

```bash
./scripts/container_smoke_test.sh
```

By default this builds an image tagged `ollama:dev` from the root `Dockerfile` and runs `ollama --version` inside the resulting container.

## Customizing the build

You can adjust the script through environment variables:

- `IMAGE_TAG` – Tag to assign to the built image (default: `ollama:dev`).
- `DOCKER_BUILDKIT` – Enables BuildKit; override if your Docker installation manages it differently (default: `1`).
- `DOCKER_BUILD_ARGS` – Additional flags to pass to `docker build`, such as `--no-cache` or `--build-arg KEY=VALUE`.

Example with a custom tag and build argument:

```bash
IMAGE_TAG=ollama:test DOCKER_BUILD_ARGS="--build-arg PARALLEL=1" ./scripts/container_smoke_test.sh
```

## Manual commands

If you prefer to run the steps manually:

1. Build the image from the repository root:
   ```bash
   DOCKER_BUILDKIT=1 docker build -t ollama:dev -f Dockerfile .
   ```

2. Run a smoke test without starting the full server:
   ```bash
   docker run --rm --entrypoint /usr/bin/ollama ollama:dev --version
   ```

The smoke test exits with a non-zero status if the binary fails to start, allowing you to catch build regressions before publishing the image.
