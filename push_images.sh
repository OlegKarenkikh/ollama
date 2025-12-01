#!/bin/bash
set -e

# Login (already done in session, but good to have)
# echo "dckr_pat_..." | docker login -u olegkarenkikh --password-stdin

# Tags
VERSION="0.0.0-20251130"

# Tag and Push Latest
if docker image inspect olegkarenkikh/ollama:latest >/dev/null 2>&1; then
    echo "Pushing latest..."
    docker push olegkarenkikh/ollama:latest

    echo "Tagging and pushing $VERSION..."
    docker tag olegkarenkikh/ollama:latest olegkarenkikh/ollama:$VERSION
    docker push olegkarenkikh/ollama:$VERSION
else
    echo "Image olegkarenkikh/ollama:latest not found. Build incomplete?"
fi

# Push ROCm
if docker image inspect olegkarenkikh/ollama:rocm >/dev/null 2>&1; then
    echo "Pushing rocm..."
    docker push olegkarenkikh/ollama:rocm
else
    echo "Image olegkarenkikh/ollama:rocm not found. Build incomplete?"
fi
