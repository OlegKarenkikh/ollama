#!/bin/sh
#
# Скрипт для push контейнеров Ollama в registry с использованием Docker Buildx
# Использует buildx imagetools для создания multi-platform манифестов
#
# Использование:
#   ./scripts/buildx_push.sh [OPTIONS]
#
# Переменные окружения:
#   VERSION             - Версия образа (автоматически из git, если не указана)
#   DOCKER_ORG          - Docker organization (по умолчанию: ollama)
#   FINAL_IMAGE_REPO    - Полное имя репозитория образа
#   REGISTRY            - Registry для push (опционально, для логина)
#   REGISTRY_USERNAME   - Username для registry
#   REGISTRY_PASSWORD   - Password для registry
#   TAG_LATEST          - Также создать тег latest (по умолчанию: пусто, не создавать)
#
# Примеры:
#   # Push с созданием тега latest
#   TAG_LATEST=1 ./scripts/buildx_push.sh
#
#   # Push в конкретный registry
#   REGISTRY=ghcr.io REGISTRY_USERNAME=user REGISTRY_PASSWORD=token ./scripts/buildx_push.sh
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

TAG_LATEST=${TAG_LATEST:-""}
REGISTRY=${REGISTRY:-""}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-""}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-""}

# Функция для логина в registry
login_to_registry() {
    if [ -n "${REGISTRY}" ] && [ -n "${REGISTRY_USERNAME}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
        echo -e "${GREEN}==> Logging in to registry: ${REGISTRY}${NC}"
        echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY}" -u "${REGISTRY_USERNAME}" --password-stdin
    fi
}

# Функция для создания multi-platform манифеста
create_manifest() {
    local source_tag="$1"
    local target_tag="$2"
    
    echo -e "${GREEN}==> Creating manifest ${target_tag} from ${source_tag}${NC}"
    docker buildx imagetools create -t "${target_tag}" "${source_tag}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}==> Successfully created manifest ${target_tag}${NC}"
    else
        echo -e "${RED}==> Failed to create manifest ${target_tag}${NC}"
        return 1
    fi
}

# Основная логика
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Ollama Container Push with Buildx${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "VERSION: ${VERSION}"
    echo "FINAL_IMAGE_REPO: ${FINAL_IMAGE_REPO}"
    echo ""
    
    # Логинимся в registry, если нужно
    login_to_registry
    
    # Создаем тег latest для основного образа, если нужно
    if [ -n "${TAG_LATEST}" ]; then
        echo ""
        echo -e "${GREEN}==> Creating latest tag${NC}"
        if ! create_manifest "${FINAL_IMAGE_REPO}:${VERSION}" "${FINAL_IMAGE_REPO}:latest"; then
            echo -e "${RED}Failed to create latest tag!${NC}"
            exit 1
        fi
    fi
    
    # Создаем тег latest для ROCM варианта, если нужно
    if [ -n "${TAG_LATEST}" ]; then
        echo ""
        echo -e "${GREEN}==> Creating rocm:latest tag${NC}"
        if ! create_manifest "${FINAL_IMAGE_REPO}:${VERSION}-rocm" "${FINAL_IMAGE_REPO}:rocm"; then
            echo -e "${YELLOW}Failed to create rocm:latest tag, but continuing...${NC}"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Push completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Запускаем основную функцию
main
