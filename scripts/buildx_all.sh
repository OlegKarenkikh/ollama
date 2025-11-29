#!/bin/sh
#
# Универсальный скрипт для сборки всех вариантов контейнеров Ollama с buildx
# Собирает все доступные Dockerfile варианты
#
# Использование:
#   ./scripts/buildx_all.sh [OPTIONS]
#
# Переменные окружения:
#   PLATFORM            - Платформы для сборки (по умолчанию: linux/amd64,linux/arm64)
#   VERSION             - Версия образа (автоматически из git, если не указана)
#   DOCKER_ORG          - Docker organization (по умолчанию: ollama)
#   FINAL_IMAGE_REPO    - Базовое имя репозитория образа
#   PUSH                - Push образы в registry (по умолчанию: пусто, не пушить)
#   BUILD_PROGRESS       - Формат прогресса сборки (по умолчанию: plain)
#   PARALLEL            - Количество параллельных процессов сборки (по умолчанию: 8)
#   BUILD_VARIANTS       - Варианты для сборки (по умолчанию: все)
#                          Формат: "dockerfile1:tag1,dockerfile2:tag2"
#
# Примеры:
#   # Сборка всех вариантов локально
#   ./scripts/buildx_all.sh
#
#   # Сборка и push всех вариантов
#   PUSH=1 ./scripts/buildx_all.sh
#
#   # Сборка только конкретных вариантов
#   BUILD_VARIANTS="Dockerfile.minimal-v2:minimal-v2,Dockerfile.cuda12amd64:cuda12amd64" ./scripts/buildx_all.sh
#

set -eu

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Загружаем общие переменные окружения
SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/env.sh"

BUILD_PROGRESS=${BUILD_PROGRESS:-"plain"}
PUSH=${PUSH:-""}
PARALLEL=${PARALLEL:-8}
BUILD_VARIANTS=${BUILD_VARIANTS:-""}

# Определяем варианты для сборки
if [ -z "${BUILD_VARIANTS}" ]; then
    # По умолчанию собираем все варианты
    VARIANTS="Dockerfile:default Dockerfile.minimal:minimal Dockerfile.minimal-v2:minimal-v2 Dockerfile.cuda12amd64:cuda12amd64"
else
    # Парсим переданные варианты
    VARIANTS=""
    IFS=',' read -r -a variant_array <<< "${BUILD_VARIANTS}"
    for variant in "${variant_array[@]}"; do
        VARIANTS="${VARIANTS} ${variant}"
    done
fi

# Определяем действие (load или push)
if [ -z "${PUSH}" ]; then
    echo -e "${YELLOW}Building images locally. Set PUSH=1 to push${NC}"
    LOAD_OR_PUSH="--load"
    # Для multi-platform сборки нельзя использовать --load
    if echo "${PLATFORM}" | grep -q ","; then
        echo -e "${RED}ERROR: Cannot use --load with multiple platforms. Use PUSH=1 to push to registry.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Will be pushing images to registry${NC}"
    LOAD_OR_PUSH="--push"
fi

# Функция для проверки и настройки buildx
setup_buildx() {
    echo -e "${GREEN}==> Setting up Docker Buildx${NC}"
    
    # Проверяем наличие buildx
    if ! docker buildx version > /dev/null 2>&1; then
        echo -e "${RED}ERROR: docker buildx is not available. Please install Docker Buildx.${NC}"
        exit 1
    fi
    
    # Используем default builder или создаем новый
    BUILDX_BUILDER="default"
    if ! docker buildx inspect "${BUILDX_BUILDER}" > /dev/null 2>&1; then
        echo -e "${YELLOW}Creating buildx builder: ${BUILDX_BUILDER}${NC}"
        docker buildx create --name "${BUILDX_BUILDER}" --use --bootstrap
    else
        docker buildx use "${BUILDX_BUILDER}"
    fi
    
    # Показываем информацию о builder
    echo -e "${GREEN}Buildx builder info:${NC}"
    docker buildx inspect --bootstrap
}

# Функция для сборки образа
build_image() {
    local platform="$1"
    local tag_suffix="$2"
    local dockerfile="$3"
    shift 3
    
    local full_tag="${FINAL_IMAGE_REPO}:${VERSION}${tag_suffix}"
    
    echo -e "${BLUE}==> Building ${full_tag}${NC}"
    echo -e "${BLUE}   Platform: ${platform}${NC}"
    echo -e "${BLUE}   Dockerfile: ${dockerfile}${NC}"
    
    docker buildx build \
        ${LOAD_OR_PUSH} \
        --progress="${BUILD_PROGRESS}" \
        --platform="${platform}" \
        --file="${dockerfile}" \
        --tag="${full_tag}" \
        ${OLLAMA_COMMON_BUILD_ARGS} \
        --build-arg PARALLEL="${PARALLEL}" \
        "$@" \
        .
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}==> ✓ Completed ${full_tag}${NC}"
        return 0
    else
        echo -e "${RED}==> ✗ Failed ${full_tag}${NC}"
        return 1
    fi
}

# Основная логика
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Ollama Multi-Variant Container Build${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "VERSION: ${VERSION}"
    echo "PLATFORM: ${PLATFORM}"
    echo "FINAL_IMAGE_REPO: ${FINAL_IMAGE_REPO}"
    echo "PARALLEL: ${PARALLEL}"
    echo "VARIANTS: ${VARIANTS}"
    echo ""
    
    # Настраиваем buildx
    setup_buildx
    
    # Счетчики успешных и неудачных сборок
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    
    # Собираем каждый вариант
    for variant in ${VARIANTS}; do
        dockerfile=$(echo "${variant}" | cut -d':' -f1)
        tag_suffix=$(echo "${variant}" | cut -d':' -f2)
        
        # Проверяем существование Dockerfile
        if [ ! -f "${dockerfile}" ]; then
            echo -e "${YELLOW}==> Skipping ${dockerfile} (file not found)${NC}"
            continue
        fi
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Building variant: ${tag_suffix}${NC}"
        echo -e "${GREEN}========================================${NC}"
        
        # Собираем основной образ
        if build_image "${PLATFORM}" "-${tag_suffix}" "${dockerfile}"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo -e "${YELLOW}Continuing with other variants...${NC}"
        fi
        
        # Если платформа включает amd64, собираем ROCM вариант
        if echo "${PLATFORM}" | grep -q "amd64"; then
            echo ""
            echo -e "${BLUE}==> Building ROCM variant for ${tag_suffix}${NC}"
            if build_image "linux/amd64" "-${tag_suffix}-rocm" "${dockerfile}" --build-arg FLAVOR=rocm; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
                echo -e "${YELLOW}ROCM build failed for ${tag_suffix}, but continuing...${NC}"
            fi
        fi
    done
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build Summary${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Successful builds: ${SUCCESS_COUNT}${NC}"
    if [ ${FAIL_COUNT} -gt 0 ]; then
        echo -e "${RED}Failed builds: ${FAIL_COUNT}${NC}"
    fi
    
    if [ ${FAIL_COUNT} -eq 0 ]; then
        echo -e "${GREEN}All builds completed successfully!${NC}"
        if [ -z "${PUSH}" ]; then
            echo -e "${YELLOW}Images are available locally.${NC}"
            echo -e "${YELLOW}To push to registry, run with PUSH=1${NC}"
        else
            echo -e "${GREEN}All images have been pushed to registry.${NC}"
        fi
        exit 0
    else
        echo -e "${RED}Some builds failed!${NC}"
        exit 1
    fi
}

# Запускаем основную функцию
main
