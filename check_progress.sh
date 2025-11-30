#!/bin/bash

LOG_FILE="/tmp/rebuild_all_final.log"
TOTAL_VARIANTS=4

echo "=== СТАТУС СБОРКИ В ПРОЦЕНТАХ ==="
echo ""

# Подсчитываем завершенные варианты
COMPLETED=0
if [ -f "$LOG_FILE" ]; then
    COMPLETED_COUNT=$(grep -c "✅ Финальный образ собран" "$LOG_FILE" 2>/dev/null)
    if [ -z "$COMPLETED_COUNT" ]; then
        COMPLETED_COUNT=0
    fi
    COMPLETED=$COMPLETED_COUNT
fi

# Проверяем текущий процесс
PROCESS_RUNNING=0
if ps aux | grep "rebuild_all_final.sh" | grep -v grep > /dev/null 2>&1; then
    PROCESS_RUNNING=1
fi

# Определяем статус каждого варианта
declare -A VARIANTS_STATUS
VARIANTS_STATUS["cuda12amd64"]="⏸️ Ожидает"
VARIANTS_STATUS["minimal"]="⏸️ Ожидает"
VARIANTS_STATUS["minimal-v2"]="⏸️ Ожидает"
VARIANTS_STATUS["astra"]="⏸️ Ожидает"

if [ -f "$LOG_FILE" ]; then
    for variant in cuda12amd64 minimal minimal-v2 astra; do
        if grep -q "✅ Финальный образ собран.*${variant}" "$LOG_FILE" 2>/dev/null; then
            VARIANTS_STATUS["${variant}"]="✅ Завершен"
        elif grep -q "🔨 Сборка финального образа.*${variant}" "$LOG_FILE" 2>/dev/null; then
            VARIANTS_STATUS["${variant}"]="⏳ В процессе"
        elif grep -q "❌ Ошибка" "$LOG_FILE" 2>/dev/null && grep -q "${variant}" "$LOG_FILE" 2>/dev/null; then
            VARIANTS_STATUS["${variant}"]="❌ Ошибка (нехватка места)"
        fi
    done
    # Пересчитываем завершенные
    COMPLETED=0
    for variant in cuda12amd64 minimal minimal-v2 astra; do
        if [ "${VARIANTS_STATUS[${variant}]}" = "✅ Завершен" ]; then
            COMPLETED=$((COMPLETED + 1))
        fi
    done
fi

# Рассчитываем прогресс
PROGRESS=$((COMPLETED * 100 / TOTAL_VARIANTS))
REMAINING=$((TOTAL_VARIANTS - COMPLETED))

echo "Всего вариантов: ${TOTAL_VARIANTS}"
echo "Завершено успешно: ${COMPLETED}"
echo "Осталось: ${REMAINING}"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "ОБЩИЙ ПРОГРЕСС: ${PROGRESS}%"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "Детали по вариантам:"
for variant in cuda12amd64 minimal minimal-v2 astra; do
    echo "  ${variant}: ${VARIANTS_STATUS[${variant}]}"
done

echo ""
echo "=== ОЦЕНКА ВРЕМЕНИ ЗАВЕРШЕНИЯ ==="
echo ""

# Оценка времени на основе предыдущих попыток
TIME_PER_VARIANT=8  # минут на вариант (с переиспользованием слоев)
ESTIMATED_MINUTES=$((REMAINING * TIME_PER_VARIANT))
ESTIMATED_HOURS=$((ESTIMATED_MINUTES / 60))
ESTIMATED_MINS=$((ESTIMATED_MINUTES % 60))

echo "На основе предыдущих попыток:"
echo "  - Загрузка образов из Docker Hub: ~2-3 минуты"
echo "  - Копирование файлов: ~1-2 минуты"
echo "  - Сборка runtime слоя: ~1-2 минуты"
echo "  - Push в Docker Hub: ~1-2 минуты"
echo ""
echo "Оценка на вариант: ~${TIME_PER_VARIANT} минут"
echo ""
echo "Осталось вариантов: ${REMAINING}"
if [ $ESTIMATED_HOURS -gt 0 ]; then
    echo "Ожидаемое время: ~${ESTIMATED_HOURS} часов ${ESTIMATED_MINS} минут"
else
    echo "Ожидаемое время: ~${ESTIMATED_MINUTES} минут"
fi

echo ""
if [ $PROCESS_RUNNING -eq 0 ]; then
    echo "⚠️  Процесс сборки НЕ запущен (упал из-за нехватки места)"
    echo "   Требуется освободить место на диске и перезапустить"
else
    echo "✅ Процесс сборки активен"
fi

echo ""
echo "Диск:"
df -h | head -2
