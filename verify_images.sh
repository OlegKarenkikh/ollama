#!/bin/bash
set -e

DOCKER_USER="olegkarenkikh"
IMAGE_NAME="ollama"
LOG_FILE="/tmp/verify_images.log"

echo "=== ПРОВЕРКА ОБРАЗОВ В DOCKER HUB ===" | tee "${LOG_FILE}"
echo "Дата: $(date)" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# Ожидаемые образы
declare -A EXPECTED_IMAGES=(
    ["cuda12amd64-cuda-builder"]="cuda12amd64-cuda-builder"
    ["cuda12amd64-go-builder"]="cuda12amd64-go-builder"
    ["cuda12amd64"]="cuda12amd64"
    ["minimal-cuda-builder"]="minimal-cuda-builder"
    ["minimal-go-builder"]="minimal-go-builder"
    ["minimal"]="minimal"
    ["minimal-v2"]="minimal-v2"
    ["astra"]="astra"
)

# Функция для получения SHA256 образа из Docker Hub
get_image_digest() {
    local tag=$1
    
    # Получаем digest через Docker Hub API v2
    local digest=$(curl -s "https://hub.docker.com/v2/repositories/${DOCKER_USER}/${IMAGE_NAME}/tags/${tag}/" \
        2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('digest', ''))" 2>/dev/null)
    
    if [ -z "$digest" ] || [ "$digest" = "None" ]; then
        # Альтернативный способ через Docker Registry API
        local token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${DOCKER_USER}/${IMAGE_NAME}:pull" \
            2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))" 2>/dev/null)
        
        if [ -n "$token" ]; then
            digest=$(curl -s -I \
                "https://registry-1.docker.io/v2/${DOCKER_USER}/${IMAGE_NAME}/manifests/${tag}" \
                -H "Authorization: Bearer ${token}" \
                2>/dev/null | grep -i "docker-content-digest" | cut -d' ' -f2 | tr -d '\r\n')
        fi
    fi
    
    echo "$digest"
}

# Функция для получения SHA256 из локального образа
get_local_image_digest() {
    local tag=$1
    local image="${DOCKER_USER}/${IMAGE_NAME}:${tag}"
    
    # Пытаемся получить digest локального образа
    sudo docker inspect "${image}" 2>/dev/null | python3 -c \
        "import sys, json; data=json.load(sys.stdin); print(data[0]['RepoDigests'][0].split('@')[1] if data[0].get('RepoDigests') else '')" 2>/dev/null || echo ""
}

# Функция для получения SHA256 из логов сборки
get_build_log_digest() {
    local tag=$1
    
    # Ищем в логах push с digest
    grep -E "pushing|pushed.*${tag}" /tmp/build_all_output.log /tmp/rebuild_variant2.log 2>/dev/null | \
        grep -oE "sha256:[a-f0-9]{64}" | head -1 || echo ""
}

echo "Проверка наличия образов в Docker Hub..." | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# Получаем список всех тегов из Docker Hub
HUB_TAGS=$(curl -s "https://hub.docker.com/v2/repositories/${DOCKER_USER}/${IMAGE_NAME}/tags?page_size=100" | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(' '.join([tag['name'] for tag in data['results']]))" 2>/dev/null)

MISSING_IMAGES=()
FOUND_IMAGES=()

for expected_tag in "${!EXPECTED_IMAGES[@]}"; do
    if echo "$HUB_TAGS" | grep -qE "\b${expected_tag}\b"; then
        echo "✓ Найден: ${expected_tag}" | tee -a "${LOG_FILE}"
        FOUND_IMAGES+=("${expected_tag}")
        
        # Получаем digest из Docker Hub
        hub_digest=$(get_image_digest "${expected_tag}")
        if [ -n "$hub_digest" ]; then
            echo "  Docker Hub SHA256: ${hub_digest}" | tee -a "${LOG_FILE}"
        fi
        
        # Пытаемся получить локальный digest
        local_digest=$(get_local_image_digest "${expected_tag}")
        if [ -n "$local_digest" ]; then
            echo "  Локальный SHA256: ${local_digest}" | tee -a "${LOG_FILE}"
            if [ "$hub_digest" = "$local_digest" ]; then
                echo "  ✅ Контрольные суммы совпадают!" | tee -a "${LOG_FILE}"
            else
                echo "  ⚠️  Контрольные суммы НЕ совпадают!" | tee -a "${LOG_FILE}"
            fi
        fi
        
        # Пытаемся найти digest в логах сборки
        log_digest=$(get_build_log_digest "${expected_tag}")
        if [ -n "$log_digest" ]; then
            echo "  SHA256 из логов: ${log_digest}" | tee -a "${LOG_FILE}"
            if [ "$hub_digest" = "$log_digest" ]; then
                echo "  ✅ Контрольная сумма из логов совпадает с Docker Hub!" | tee -a "${LOG_FILE}"
            fi
        fi
        
        echo "" | tee -a "${LOG_FILE}"
    else
        echo "✗ Отсутствует: ${expected_tag}" | tee -a "${LOG_FILE}"
        MISSING_IMAGES+=("${expected_tag}")
        echo "" | tee -a "${LOG_FILE}"
    fi
done

echo "════════════════════════════════════════════════════════════════" | tee -a "${LOG_FILE}"
echo "РЕЗУЛЬТАТЫ ПРОВЕРКИ:" | tee -a "${LOG_FILE}"
echo "════════════════════════════════════════════════════════════════" | tee -a "${LOG_FILE}"
echo "Найдено образов: ${#FOUND_IMAGES[@]}" | tee -a "${LOG_FILE}"
echo "Отсутствует образов: ${#MISSING_IMAGES[@]}" | tee -a "${LOG_FILE}"

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    echo "" | tee -a "${LOG_FILE}"
    echo "Отсутствующие образы:" | tee -a "${LOG_FILE}"
    for img in "${MISSING_IMAGES[@]}"; do
        echo "  - ${img}" | tee -a "${LOG_FILE}"
    done
fi

echo "" | tee -a "${LOG_FILE}"
echo "Полный лог проверки сохранен в: ${LOG_FILE}" | tee -a "${LOG_FILE}"

if [ ${#MISSING_IMAGES[@]} -eq 0 ]; then
    echo "✅ Все ожидаемые образы найдены в Docker Hub!" | tee -a "${LOG_FILE}"
    exit 0
else
    echo "❌ Некоторые образы отсутствуют в Docker Hub" | tee -a "${LOG_FILE}"
    exit 1
fi
