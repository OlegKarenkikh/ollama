#!/bin/bash
set -e

DOCKER_USER="olegkarenkikh"
IMAGE_NAME="ollama"
TAG_BASE="cuda12amd64"
LOG_FILE="/tmp/docker_build_cuda12amd64.log"

echo "=== СБОРКА С ПРОМЕЖУТОЧНЫМИ PUSH В DOCKER HUB ==="
echo ""

# Функция для push образа
push_image() {
    local tag=$1
    local image="${DOCKER_USER}/${IMAGE_NAME}:${tag}"
    echo "📤 Push образа: ${image}"
    if sudo docker push "${image}" 2>&1 | tee -a "${LOG_FILE}"; then
        echo "✅ Успешно запушен: ${image}"
        return 0
    else
        echo "❌ Ошибка при push: ${image}"
        return 1
    fi
}

# Этап 1: CUDA builder
echo "🔨 Этап 1: Сборка CUDA builder..."
if sudo docker build \
    --target cuda-builder \
    -f Dockerfile.cuda12amd64 \
    -t "${DOCKER_USER}/${IMAGE_NAME}:${TAG_BASE}-cuda-builder" \
    . 2>&1 | tee -a "${LOG_FILE}"; then
    echo "✅ CUDA builder собран"
    push_image "${TAG_BASE}-cuda-builder"
else
    echo "❌ Ошибка сборки CUDA builder"
    exit 1
fi

# Этап 2: Go builder
echo ""
echo "🔨 Этап 2: Сборка Go builder..."
if sudo docker build \
    --target go-builder \
    -f Dockerfile.cuda12amd64 \
    -t "${DOCKER_USER}/${IMAGE_NAME}:${TAG_BASE}-go-builder" \
    . 2>&1 | tee -a "${LOG_FILE}"; then
    echo "✅ Go builder собран"
    push_image "${TAG_BASE}-go-builder"
else
    echo "❌ Ошибка сборки Go builder"
    exit 1
fi

# Этап 3: Финальный образ
echo ""
echo "🔨 Этап 3: Сборка финального образа..."
if sudo docker build \
    -f Dockerfile.cuda12amd64 \
    -t "${DOCKER_USER}/${IMAGE_NAME}:${TAG_BASE}" \
    . 2>&1 | tee -a "${LOG_FILE}"; then
    echo "✅ Финальный образ собран"
    push_image "${TAG_BASE}"
    echo ""
    echo "🎉 ВСЕ ЭТАПЫ ЗАВЕРШЕНЫ УСПЕШНО!"
    echo ""
    echo "Собранные образы:"
    sudo docker images "${DOCKER_USER}/${IMAGE_NAME}" | grep "${TAG_BASE}"
else
    echo "❌ Ошибка сборки финального образа"
    exit 1
fi
