#!/bin/bash
set -e

DOCKER_USER="olegkarenkikh"
IMAGE_NAME="ollama"
LOG_FILE="/tmp/verify_images_final.log"

echo "=== ФИНАЛЬНАЯ ПРОВЕРКА ОБРАЗОВ В DOCKER HUB ===" | tee "${LOG_FILE}"
echo "Дата: $(date)" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# Ожидаемые образы с их тегами
declare -A EXPECTED_IMAGES=(
    ["cuda12amd64-cuda-builder"]="cuda12amd64-cuda-builder"
    ["cuda12amd64-go-builder"]="cuda12amd64-go-builder"
    ["cuda12amd64"]="cuda12amd64"
    ["minimal"]="minimal"
    ["minimal-v2"]="minimal-v2"
    ["astra"]="astra"
)

# Функция для получения digest образа из Docker Hub через Registry API
get_image_digest_from_registry() {
    local tag=$1
    
    # Получаем токен авторизации
    local token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${DOCKER_USER}/${IMAGE_NAME}:pull" \
        2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))" 2>/dev/null)
    
    if [ -z "$token" ]; then
        return 1
    fi
    
    # Получаем manifest и извлекаем digest
    local response=$(curl -s -I \
        "https://registry-1.docker.io/v2/${DOCKER_USER}/${IMAGE_NAME}/manifests/${tag}" \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        2>/dev/null)
    
    local digest=$(echo "$response" | grep -i "docker-content-digest" | cut -d' ' -f2 | tr -d '\r\n')
    echo "$digest"
}

# Функция для получения digest из логов сборки
get_digest_from_logs() {
    local tag=$1
    local log_files="/tmp/build_all_output.log /tmp/rebuild_variant2.log"
    
    # Ищем push с указанным тегом
    for log_file in $log_files; do
        if [ -f "$log_file" ]; then
            local digest=$(grep -E "pushing.*${tag}|pushed.*${tag}" "$log_file" 2>/dev/null | \
                grep -oE "sha256:[a-f0-9]{64}" | head -1)
            if [ -n "$digest" ]; then
                echo "$digest"
                return 0
            fi
        fi
    done
    
    # Альтернативный поиск - ищем по имени образа в manifest
    for log_file in $log_files; do
        if [ -f "$log_file" ]; then
            local digest=$(grep -E "olegkarenkikh/ollama:${tag}@sha256" "$log_file" 2>/dev/null | \
                grep -oE "sha256:[a-f0-9]{64}" | head -1)
            if [ -n "$digest" ]; then
                echo "$digest"
                return 0
            fi
        fi
    done
    
    echo ""
}

# Функция для получения digest через docker pull и inspect
get_digest_via_pull() {
    local tag=$1
    local image="${DOCKER_USER}/${IMAGE_NAME}:${tag}"
    
    # Пытаемся скачать образ
    if sudo docker pull "${image}" >/dev/null 2>&1; then
        # Получаем digest из локального образа
        local digest=$(sudo docker inspect "${image}" 2>/dev/null | python3 -c \
            "import sys, json; data=json.load(sys.stdin); print(data[0]['RepoDigests'][0].split('@')[1] if data[0].get('RepoDigests') and len(data[0]['RepoDigests']) > 0 else '')" 2>/dev/null)
        echo "$digest"
    else
        echo ""
    fi
}

echo "Получение списка образов из Docker Hub..." | tee -a "${LOG_FILE}"
HUB_TAGS=$(curl -s "https://hub.docker.com/v2/repositories/${DOCKER_USER}/${IMAGE_NAME}/tags?page_size=100" | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(' '.join([tag['name'] for tag in data['results']]))" 2>/dev/null)

echo "Проверка образов..." | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

MISSING_IMAGES=()
FOUND_IMAGES=()
VERIFICATION_RESULTS=()

for expected_tag in "${!EXPECTED_IMAGES[@]}"; do
    echo "Проверка: ${expected_tag}" | tee -a "${LOG_FILE}"
    
    if echo "$HUB_TAGS" | grep -qE "\b${expected_tag}\b"; then
        echo "  ✓ Образ найден в Docker Hub" | tee -a "${LOG_FILE}"
        FOUND_IMAGES+=("${expected_tag}")
        
        # Получаем digest из Registry API
        hub_digest=$(get_image_digest_from_registry "${expected_tag}")
        if [ -n "$hub_digest" ]; then
            echo "  Docker Hub Digest: ${hub_digest}" | tee -a "${LOG_FILE}"
        else
            echo "  ⚠️  Не удалось получить digest из Registry API" | tee -a "${LOG_FILE}"
        fi
        
        # Получаем digest из логов
        log_digest=$(get_digest_from_logs "${expected_tag}")
        if [ -n "$log_digest" ]; then
            echo "  Digest из логов: ${log_digest}" | tee -a "${LOG_FILE}"
            
            if [ -n "$hub_digest" ] && [ "$hub_digest" = "$log_digest" ]; then
                echo "  ✅ Контрольные суммы СОВПАДАЮТ!" | tee -a "${LOG_FILE}"
                VERIFICATION_RESULTS+=("${expected_tag}:MATCH")
            elif [ -n "$hub_digest" ] && [ "$hub_digest" != "$log_digest" ]; then
                echo "  ⚠️  Контрольные суммы НЕ совпадают!" | tee -a "${LOG_FILE}"
                VERIFICATION_RESULTS+=("${expected_tag}:MISMATCH")
            else
                echo "  ⚠️  Не удалось сравнить (нет digest из Registry)" | tee -a "${LOG_FILE}"
                VERIFICATION_RESULTS+=("${expected_tag}:UNKNOWN")
            fi
        else
            echo "  ⚠️  Digest не найден в логах сборки" | tee -a "${LOG_FILE}"
            VERIFICATION_RESULTS+=("${expected_tag}:NO_LOG")
        fi
        
        # Дополнительная проверка через docker pull
        echo "  Проверка через docker pull..." | tee -a "${LOG_FILE}"
        pull_digest=$(get_digest_via_pull "${expected_tag}")
        if [ -n "$pull_digest" ]; then
            echo "  Digest через pull: ${pull_digest}" | tee -a "${LOG_FILE}"
            if [ -n "$hub_digest" ] && [ "$hub_digest" = "$pull_digest" ]; then
                echo "  ✅ Digest через pull совпадает с Registry API!" | tee -a "${LOG_FILE}"
            fi
        else
            echo "  ⚠️  Не удалось скачать образ для проверки" | tee -a "${LOG_FILE}"
        fi
        
    else
        echo "  ✗ Образ ОТСУТСТВУЕТ в Docker Hub" | tee -a "${LOG_FILE}"
        MISSING_IMAGES+=("${expected_tag}")
        VERIFICATION_RESULTS+=("${expected_tag}:MISSING")
    fi
    
    echo "" | tee -a "${LOG_FILE}"
done

echo "════════════════════════════════════════════════════════════════" | tee -a "${LOG_FILE}"
echo "ИТОГОВЫЕ РЕЗУЛЬТАТЫ ПРОВЕРКИ:" | tee -a "${LOG_FILE}"
echo "════════════════════════════════════════════════════════════════" | tee -a "${LOG_FILE}"
echo "Найдено образов: ${#FOUND_IMAGES[@]}" | tee -a "${LOG_FILE}"
echo "Отсутствует образов: ${#MISSING_IMAGES[@]}" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    echo "Отсутствующие образы:" | tee -a "${LOG_FILE}"
    for img in "${MISSING_IMAGES[@]}"; do
        echo "  - ${img}" | tee -a "${LOG_FILE}"
    done
    echo "" | tee -a "${LOG_FILE}"
fi

echo "Детали проверки контрольных сумм:" | tee -a "${LOG_FILE}"
for result in "${VERIFICATION_RESULTS[@]}"; do
    tag=$(echo "$result" | cut -d':' -f1)
    status=$(echo "$result" | cut -d':' -f2)
    case "$status" in
        MATCH)
            echo "  ✅ ${tag}: контрольные суммы совпадают" | tee -a "${LOG_FILE}"
            ;;
        MISMATCH)
            echo "  ⚠️  ${tag}: контрольные суммы НЕ совпадают" | tee -a "${LOG_FILE}"
            ;;
        MISSING)
            echo "  ✗ ${tag}: образ отсутствует в Docker Hub" | tee -a "${LOG_FILE}"
            ;;
        NO_LOG)
            echo "  ⚠️  ${tag}: digest не найден в логах" | tee -a "${LOG_FILE}"
            ;;
        UNKNOWN)
            echo "  ⚠️  ${tag}: не удалось проверить" | tee -a "${LOG_FILE}"
            ;;
    esac
done

echo "" | tee -a "${LOG_FILE}"
echo "Полный лог проверки сохранен в: ${LOG_FILE}" | tee -a "${LOG_FILE}"

# Определяем код выхода
if [ ${#MISSING_IMAGES[@]} -eq 0 ]; then
    # Проверяем, все ли контрольные суммы совпадают
    mismatch_count=$(echo "${VERIFICATION_RESULTS[@]}" | grep -o "MISMATCH" | wc -l)
    if [ "$mismatch_count" -eq 0 ]; then
        echo "✅ Все образы найдены и контрольные суммы совпадают!" | tee -a "${LOG_FILE}"
        exit 0
    else
        echo "⚠️  Все образы найдены, но есть несовпадения контрольных сумм" | tee -a "${LOG_FILE}"
        exit 1
    fi
else
    echo "❌ Некоторые образы отсутствуют в Docker Hub" | tee -a "${LOG_FILE}"
    exit 1
fi
