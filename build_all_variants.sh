#!/bin/bash
set -e

DOCKER_USER="olegkarenkikh"
IMAGE_NAME="ollama"
LOG_FILE="/tmp/docker_build_all_variants.log"

# Создаем лог-файл с правильными правами
sudo touch "${LOG_FILE}"
sudo chmod 666 "${LOG_FILE}"

echo "=== СБОРКА ВСЕХ ВАРИАНТОВ КОНТЕЙНЕРОВ С ПРОМЕЖУТОЧНЫМИ PUSH ==="
echo "Логирование в: ${LOG_FILE}"
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

# Функция для сборки и push этапа
build_and_push_stage() {
    local dockerfile=$1
    local stage=$2
    local tag=$3
    local build_args=$4
    
    echo "🔨 Сборка этапа ${stage} из ${dockerfile}..."
    if sudo docker buildx build \
        --platform linux/amd64 \
        --target "${stage}" \
        -f "${dockerfile}" \
        -t "${DOCKER_USER}/${IMAGE_NAME}:${tag}" \
        --push \
        ${build_args} \
        . 2>&1 | tee -a "${LOG_FILE}"; then
        echo "✅ Этап ${stage} собран и запушен: ${tag}"
        return 0
    else
        echo "❌ Ошибка сборки этапа ${stage}"
        return 1
    fi
}

# Функция для сборки финального образа
build_final_image() {
    local dockerfile=$1
    local tag=$2
    local build_args=$3
    
    echo "🔨 Сборка финального образа из ${dockerfile}..."
    if sudo docker buildx build \
        --platform linux/amd64 \
        -f "${dockerfile}" \
        -t "${DOCKER_USER}/${IMAGE_NAME}:${tag}" \
        --push \
        ${build_args} \
        . 2>&1 | tee -a "${LOG_FILE}"; then
        echo "✅ Финальный образ собран и запушен: ${tag}"
        return 0
    else
        echo "❌ Ошибка сборки финального образа"
        return 1
    fi
}

# ============================================================================
# ВАРИАНТ 1: Dockerfile.cuda12amd64
# ============================================================================
echo "════════════════════════════════════════════════════════════════"
echo "ВАРИАНТ 1: Dockerfile.cuda12amd64"
echo "════════════════════════════════════════════════════════════════"

# Этап 1: CUDA builder
build_and_push_stage "Dockerfile.cuda12amd64" "cuda-builder" "cuda12amd64-cuda-builder" ""

# Этап 2: Go builder
build_and_push_stage "Dockerfile.cuda12amd64" "go-builder" "cuda12amd64-go-builder" ""

# Финальный образ
build_final_image "Dockerfile.cuda12amd64" "cuda12amd64" ""

echo ""

# ============================================================================
# ВАРИАНТ 2: Dockerfile.minimal
# ============================================================================
echo "════════════════════════════════════════════════════════════════"
echo "ВАРИАНТ 2: Dockerfile.minimal"
echo "════════════════════════════════════════════════════════════════"

# Этап 1: CUDA builder
build_and_push_stage "Dockerfile.minimal" "cuda-builder" "minimal-cuda-builder" ""

# Этап 2: Go builder
build_and_push_stage "Dockerfile.minimal" "go-builder" "minimal-go-builder" ""

# Финальный образ
build_final_image "Dockerfile.minimal" "minimal" ""

echo ""

# ============================================================================
# ВАРИАНТ 3: Dockerfile.minimal-v2
# ============================================================================
echo "════════════════════════════════════════════════════════════════"
echo "ВАРИАНТ 3: Dockerfile.minimal-v2"
echo "════════════════════════════════════════════════════════════════"

# Этап 1: CUDA builder
build_and_push_stage "Dockerfile.minimal-v2" "cuda-builder" "minimal-v2-cuda-builder" ""

# Этап 2: Go builder
build_and_push_stage "Dockerfile.minimal-v2" "go-builder" "minimal-v2-go-builder" ""

# Финальный образ
build_final_image "Dockerfile.minimal-v2" "minimal-v2" ""

echo ""

# ============================================================================
# ВАРИАНТ 4: Dockerfile (основной с Astra Linux UBI)
# ============================================================================
echo "════════════════════════════════════════════════════════════════"
echo "ВАРИАНТ 4: Dockerfile (Astra Linux UBI)"
echo "════════════════════════════════════════════════════════════════"

# Этап 1: Python source
build_and_push_stage "Dockerfile" "python-source" "astra-python-source" ""

# Этап 2: Base
build_and_push_stage "Dockerfile" "base" "astra-base" ""

# Этап 3: CPU backend
build_and_push_stage "Dockerfile" "cpu" "astra-cpu" ""

# Этап 4: CUDA builder
build_and_push_stage "Dockerfile" "cuda-builder" "astra-cuda-builder" ""

# Этап 5: Go builder
build_and_push_stage "Dockerfile" "go-builder" "astra-go-builder" ""

# Финальный образ
build_final_image "Dockerfile" "astra" "--build-arg PARALLEL=8"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🎉 ВСЕ ВАРИАНТЫ КОНТЕЙНЕРОВ СОБРАНЫ И ЗАПУШЕНЫ!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Собранные образы:"
sudo docker images "${DOCKER_USER}/${IMAGE_NAME}" | head -20
