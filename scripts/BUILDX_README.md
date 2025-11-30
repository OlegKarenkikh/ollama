# Docker Buildx - Инструкции по сборке контейнеров

Этот документ описывает процесс сборки контейнеров Ollama с использованием Docker Buildx для multi-platform сборки.

## Предварительные требования

1. **Docker с поддержкой Buildx**
   ```bash
   docker buildx version
   ```
   Если команда не работает, установите Docker Buildx:
   ```bash
   # Для Linux
   docker buildx install
   
   # Или используйте плагин
   docker plugin install docker/buildx
   ```

2. **Настройка Buildx builder**
   ```bash
   # Создать новый builder (опционально)
   docker buildx create --name ollama-builder --use --bootstrap
   
   # Или использовать default builder
   docker buildx use default
   ```

3. **Для multi-platform сборки (опционально)**
   ```bash
   # Установить QEMU для эмуляции других архитектур
   docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
   ```

## Доступные скрипты

### 1. `buildx_build.sh` - Базовая сборка

Собирает один Dockerfile с поддержкой multi-platform.

**Использование:**
```bash
# Локальная сборка для одной платформы
PLATFORM=linux/amd64 ./scripts/buildx_build.sh

# Сборка и push для multi-platform
PUSH=1 PLATFORM=linux/amd64,linux/arm64 ./scripts/buildx_build.sh

# Сборка конкретного Dockerfile
DOCKERFILE=Dockerfile.minimal-v2 ./scripts/buildx_build.sh
```

**Переменные окружения:**
- `DOCKERFILE` - Путь к Dockerfile (по умолчанию: `Dockerfile`)
- `PLATFORM` - Платформы для сборки (по умолчанию: `linux/amd64,linux/arm64`)
- `VERSION` - Версия образа (автоматически из git, если не указана)
- `DOCKER_ORG` - Docker organization (по умолчанию: `ollama`)
- `FINAL_IMAGE_REPO` - Полное имя репозитория образа
- `PUSH` - Push образы в registry (по умолчанию: пусто, не пушить)
- `BUILDX_BUILDER` - Имя buildx builder (по умолчанию: `ollama-builder`)
- `BUILD_PROGRESS` - Формат прогресса сборки (по умолчанию: `plain`)
- `PARALLEL` - Количество параллельных процессов сборки (по умолчанию: `8`)

### 2. `buildx_push.sh` - Создание манифестов и тегов

Создает multi-platform манифесты и теги (например, `latest`).

**Использование:**
```bash
# Создать тег latest
TAG_LATEST=1 ./scripts/buildx_push.sh

# Push в конкретный registry
REGISTRY=ghcr.io REGISTRY_USERNAME=user REGISTRY_PASSWORD=token TAG_LATEST=1 ./scripts/buildx_push.sh
```

**Переменные окружения:**
- `VERSION` - Версия образа
- `DOCKER_ORG` - Docker organization
- `FINAL_IMAGE_REPO` - Полное имя репозитория образа
- `REGISTRY` - Registry для push (опционально)
- `REGISTRY_USERNAME` - Username для registry
- `REGISTRY_PASSWORD` - Password для registry
- `TAG_LATEST` - Также создать тег latest (по умолчанию: пусто)

### 3. `buildx_all.sh` - Сборка всех вариантов

Собирает все доступные варианты Dockerfile.

**Использование:**
```bash
# Сборка всех вариантов локально
./scripts/buildx_all.sh

# Сборка и push всех вариантов
PUSH=1 ./scripts/buildx_all.sh

# Сборка только конкретных вариантов
BUILD_VARIANTS="Dockerfile.minimal-v2:minimal-v2,Dockerfile.cuda12amd64:cuda12amd64" ./scripts/buildx_all.sh
```

**Переменные окружения:**
- `PLATFORM` - Платформы для сборки (по умолчанию: `linux/amd64,linux/arm64`)
- `VERSION` - Версия образа
- `DOCKER_ORG` - Docker organization
- `FINAL_IMAGE_REPO` - Базовое имя репозитория образа
- `PUSH` - Push образы в registry
- `BUILD_PROGRESS` - Формат прогресса сборки
- `PARALLEL` - Количество параллельных процессов сборки
- `BUILD_VARIANTS` - Варианты для сборки (по умолчанию: все)
  - Формат: `"dockerfile1:tag1,dockerfile2:tag2"`

## Доступные Dockerfile варианты

1. **Dockerfile** - Основной Dockerfile (Astra Linux UBI 1.8.1)
2. **Dockerfile.minimal** - Минимальный вариант (Ubuntu + CUDA 12)
3. **Dockerfile.minimal-v2** - Ультра-минимальный вариант
4. **Dockerfile.cuda12amd64** - CUDA 12 AMD64 только

## Примеры использования

### Пример 1: Локальная сборка для разработки

```bash
# Сборка для локальной разработки (только amd64)
PLATFORM=linux/amd64 DOCKERFILE=Dockerfile.minimal-v2 ./scripts/buildx_build.sh

# Проверка образа
docker run --rm ollama/ollama:0.0.0-minimal-v2 --version
```

### Пример 2: Сборка и push в GitHub Container Registry

```bash
# Настройка переменных
export FINAL_IMAGE_REPO=ghcr.io/username/ollama
export VERSION=1.0.0
export REGISTRY=ghcr.io
export REGISTRY_USERNAME=username
export REGISTRY_PASSWORD=ghp_token

# Логин в registry
echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY}" -u "${REGISTRY_USERNAME}" --password-stdin

# Сборка и push
PUSH=1 PLATFORM=linux/amd64,linux/arm64 ./scripts/buildx_build.sh

# Создание тега latest
TAG_LATEST=1 ./scripts/buildx_push.sh
```

### Пример 3: Сборка всех вариантов для релиза

```bash
# Настройка версии
export VERSION=$(git describe --tags --first-parent --abbrev=7 --long --dirty --always | sed -e "s/^v//g")
export FINAL_IMAGE_REPO=myregistry.com/ollama

# Сборка всех вариантов
PUSH=1 PLATFORM=linux/amd64,linux/arm64 ./scripts/buildx_all.sh
```

### Пример 4: Сборка только конкретного варианта

```bash
# Только минимальный вариант
BUILD_VARIANTS="Dockerfile.minimal-v2:minimal-v2" PUSH=1 ./scripts/buildx_all.sh
```

## Troubleshooting

### Проблема: "Cannot use --load with multiple platforms"

**Решение:** Для multi-platform сборки необходимо использовать `PUSH=1` и push в registry. Локальная сборка (`--load`) поддерживает только одну платформу.

### Проблема: "docker buildx is not available"

**Решение:** Установите Docker Buildx:
```bash
# Для Docker Desktop - уже включен
# Для Linux
docker buildx install
```

### Проблема: Медленная сборка для других архитектур

**Решение:** Используйте remote builders или native builders для каждой архитектуры:
```bash
# Создать remote builder для amd64
docker context create amd64-builder --docker host=ssh://amd64-host
docker buildx create --name multi-builder amd64-builder --platform linux/amd64

# Добавить arm64 builder
docker buildx create --name multi-builder --append default --platform linux/arm64
docker buildx use multi-builder
```

### Проблема: Ошибки при сборке CUDA вариантов

**Решение:** Убедитесь, что базовый образ CUDA доступен:
```bash
docker pull nvidia/cuda:12.8.0-devel-ubuntu22.04
```

## Дополнительные ресурсы

- [Docker Buildx документация](https://docs.docker.com/buildx/)
- [Multi-platform images](https://docs.docker.com/build/building/multi-platform/)
- [Buildx imagetools](https://docs.docker.com/engine/reference/commandline/buildx_imagetools/)
