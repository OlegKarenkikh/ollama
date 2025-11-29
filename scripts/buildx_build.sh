#!/bin/sh
#
# Скрипт для сборки контейнеров Ollama с использованием Docker Buildx
# Поддерживает multi-platform сборку и push в registry
#
# Использование:
#   ./scripts/buildx_build.sh [OPTIONS]
#
# Переменные окружения:
#   DOCKERFILE          - Путь к Dockerfile (по умолчанию: Dockerfile)
#   PLATFORM            - Платформы для сборки (по умолчанию: linux/amd64,linux/arm64)
#   VERSION             - Версия образа (автоматически из git, если не указана)
#   DOCKER_ORG          - Docker organization (по умолчанию: ollama)
#   FINAL_IMAGE_REPO    - Полное имя репозитория образа
#   PUSH                - Push образы в registry (по умолчанию: пусто, не пушить)
#   BUILDX_BUILDER      - Имя buildx builder (по умолчанию: ollama-builder)
#   BUILD_PROGRESS       - Формат прогресса сборки (по умолчанию: plain)
#   PARALLEL            - Количество параллельных процессов сборки (по умолчанию: 8)
#
# Примеры:
#   # Локальная сборка для одной платформы
#   PLATFORM=linux/amd64 ./scripts/buildx_build.sh
#
#   # Сборка и push для multi-platform
#   PUSH=1 PLATFORM=linux/amd64,linux/arm64 ./scripts/buildx_build.sh
#
#   # Сборка конкретного Dockerfile
#   DOCKERFILE=Dockerfile.minimal-v2 ./scripts/buildx_build.sh
#

set -eu

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Загружаем общие переменные окружения
SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/env.sh"

# Переопределяем переменные, если нужно
DOCKERFILE=${DOCKERFILE:-"Dockerfile"}
BUILDX_BUILDER=${BUILDX_BUILDER:-"ollama-builder"}
BUILD_PROGRESS=${BUILD_PROGRESS:-"plain"}
PUSH=${PUSH:-""}
PARALLEL=${PARALLEL:-8}

# Определяем действие (load или push)
if [ -z "${PUSH}" ]; then
    echo -e "${YELLOW}Building ${FINAL_IMAGE_REPO}:${VERSION} locally. Set PUSH=1 to push${NC}"
    LOAD_OR_PUSH="--load"
    # Для multi-platform сборки нельзя использовать --load
    if echo "${PLATFORM}" | grep -q ","; then
        echo -e "${RED}ERROR: Cannot use --load with multiple platforms. Use PUSH=1 to push to registry.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Will be pushing ${FINAL_IMAGE_REPO}:${VERSION}${NC}"
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
    
    # Проверяем существование builder
    if ! docker buildx inspect "${BUILDX_BUILDER}" > /dev/null 2>&1; then
        echo -e "${YELLOW}Creating buildx builder: ${BUILDX_BUILDER}${NC}"
        docker buildx create --name "${BUILDX_BUILDER}" --use --bootstrap
    else
        echo -e "${GREEN}Using existing buildx builder: ${BUILDX_BUILDER}${NC}"
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
    
    echo -e "${GREEN}==> Building ${full_tag} for platform ${platform} (progress: ${BUILD_PROGRESS})${NC}"
    echo -e "${GREEN}   Dockerfile: ${dockerfile}${NC}"
    
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
        echo -e "${GREEN}==> Completed ${full_tag} for platform ${platform}${NC}"
    else
        echo -e "${RED}==> Failed ${full_tag} for platform ${platform}${NC}"
        return 1
    fi
}

# Основная логика
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Ollama Container Build with Buildx${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "VERSION: ${VERSION}"
    echo "PLATFORM: ${PLATFORM}"
    echo "DOCKERFILE: ${DOCKERFILE}"
    echo "FINAL_IMAGE_REPO: ${FINAL_IMAGE_REPO}"
    echo "BUILDX_BUILDER: ${BUILDX_BUILDER}"
    echo "PARALLEL: ${PARALLEL}"
    echo ""
    
    # Настраиваем buildx
    setup_buildx
    
    # Собираем основной образ
    if ! build_image "${PLATFORM}" "" "${DOCKERFILE}"; then
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
    
    # Если платформа включает amd64, собираем ROCM вариант
    if echo "${PLATFORM}" | grep -q "amd64"; then
        echo ""
        echo -e "${GREEN}==> Building ROCM variant for amd64${NC}"
        if ! build_image "linux/amd64" "-rocm" "${DOCKERFILE}" --build-arg FLAVOR=rocm; then
            echo -e "${YELLOW}ROCM build failed, but continuing...${NC}"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    if [ -z "${PUSH}" ]; then
        echo -e "${YELLOW}Images are available locally.${NC}"
        echo -e "${YELLOW}To push to registry, run with PUSH=1${NC}"
    else
        echo -e "${GREEN}Images have been pushed to registry.${NC}"
    fi
}

# Запускаем основную функцию
main
