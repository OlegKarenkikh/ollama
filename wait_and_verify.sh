#!/bin/bash
set -e

echo "=== ОЖИДАНИЕ ЗАВЕРШЕНИЯ СБОРКИ И ПРОВЕРКА ОБРАЗОВ ==="
echo ""

# Функция для проверки завершения процессов
check_processes() {
    local rebuild_running=$(ps aux | grep "rebuild_variant2.sh" | grep -v grep | wc -l)
    local build_running=$(ps aux | grep "build_all_variants.sh" | grep -v grep | wc -l)
    
    if [ "$rebuild_running" -eq 0 ] && [ "$build_running" -eq 0 ]; then
        return 0  # Все процессы завершены
    else
        return 1  # Процессы еще работают
    fi
}

# Ожидание завершения процессов
echo "Ожидание завершения процессов сборки..."
MAX_WAIT=3600  # Максимум 1 час
ELAPSED=0
CHECK_INTERVAL=60  # Проверка каждую минуту

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if check_processes; then
        echo "✅ Все процессы сборки завершены!"
        break
    fi
    
    echo "Процессы еще работают... (прошло ${ELAPSED} секунд)"
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  Достигнут лимит времени ожидания. Проверяю текущее состояние..."
fi

echo ""
echo "Запуск проверки образов..."
echo ""

# Запускаем финальную проверку
bash /workspace/verify_images_final.sh

echo ""
echo "=== ДОПОЛНИТЕЛЬНАЯ ПРОВЕРКА ЧЕРЕЗ DOCKER PULL ==="
echo ""

# Пытаемся скачать образы и проверить их digest
for tag in cuda12amd64-cuda-builder cuda12amd64-go-builder cuda12amd64 minimal; do
    echo "Проверка образа: ${tag}"
    if sudo docker pull "olegkarenkikh/ollama:${tag}" 2>&1 | head -5; then
        echo "  ✅ Образ успешно скачан"
        sudo docker inspect "olegkarenkikh/ollama:${tag}" 2>/dev/null | python3 -c \
            "import sys, json; data=json.load(sys.stdin); print('  Digest:', data[0]['RepoDigests'][0] if data[0].get('RepoDigests') else 'N/A')" 2>/dev/null || echo "  ⚠️  Не удалось получить digest"
    else
        echo "  ❌ Не удалось скачать образ"
    fi
    echo ""
done

echo "Проверка завершена!"
