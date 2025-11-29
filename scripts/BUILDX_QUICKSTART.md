# Быстрый старт - Сборка контейнеров с Buildx

## Подготовка

1. **Проверка Docker Buildx:**
   ```bash
   docker buildx version
   ```

2. **Настройка builder (если нужно):**
   ```bash
   docker buildx create --name ollama-builder --use --bootstrap
   ```

## Базовые команды

### Сборка одного образа

```bash
# Локальная сборка (только amd64)
PLATFORM=linux/amd64 ./scripts/buildx_build.sh

# Multi-platform сборка с push
PUSH=1 PLATFORM=linux/amd64,linux/arm64 ./scripts/buildx_build.sh
```

### Сборка всех вариантов

```bash
# Все варианты локально
./scripts/buildx_all.sh

# Все варианты с push
PUSH=1 ./scripts/buildx_all.sh
```

### Создание тега latest

```bash
# После сборки и push
TAG_LATEST=1 ./scripts/buildx_push.sh
```

## Примеры для разных сценариев

### Разработка (локально)
```bash
PLATFORM=linux/amd64 DOCKERFILE=Dockerfile.minimal-v2 ./scripts/buildx_build.sh
```

### Релиз (multi-platform)
```bash
export VERSION=1.0.0
export FINAL_IMAGE_REPO=myregistry.com/ollama
PUSH=1 PLATFORM=linux/amd64,linux/arm64 ./scripts/buildx_build.sh
TAG_LATEST=1 ./scripts/buildx_push.sh
```

### Только конкретный вариант
```bash
BUILD_VARIANTS="Dockerfile.cuda12amd64:cuda12amd64" PUSH=1 ./scripts/buildx_all.sh
```

## Важные замечания

- Для multi-platform сборки **обязательно** используйте `PUSH=1` (локальная сборка поддерживает только одну платформу)
- Версия образа определяется автоматически из git, если не указана через `VERSION`
- По умолчанию собираются платформы: `linux/amd64,linux/arm64`
- Все скрипты используют переменные из `scripts/env.sh`

## Полная документация

См. `scripts/BUILDX_README.md` для подробной документации.
