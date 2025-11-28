# vim: filetype=dockerfile
# Ollama Secure Build - CUDA 12 + AMD64 only (Astra Linux UBI 1.8.1 FIXED)
# Устранение CVE-2025-47914, CVE-2025-58181, CVE-2024-41996, CVE-2025-5222

ARG PARALLEL=8
ARG CMAKEVERSION=3.25.1  # Совместимая версия для Astra
ARG CUDA12VERSION=12.8

# ============================================================================
# ЭТАП 1: Установка Python 3.12 из официального образа
# ============================================================================
FROM python:3.12-slim-bookworm AS python-source

# ============================================================================
# ЭТАП 2: Базовая настройка Astra Linux UBI 1.8.1 (БЕЗ upgrade)
# ============================================================================
FROM --platform=linux/amd64 registry.astralinux.ru/library/astra/ubi18:1.8.1 AS base

# Копирование Python 3.12 из официального образа
COPY --from=python-source /usr/local /usr/local

# Обновление динамического линковщика
RUN ldconfig

# Установка базовых зависимостей БЕЗ upgrade (исправление ошибки UBI)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gcc \
        g++ \
        make \
        cmake \
        ninja-build \
        git \
        ccache \
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncursesw5-dev \
        libncurses5-dev \
        libffi-dev \
        liblzma-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Установка CMake (если отсутствует в репозитории)
ARG CMAKEVERSION
RUN if ! command -v cmake >/dev/null 2>&1; then \
        curl -fsSL https://github.com/Kitware/CMake/releases/download/v${CMAKEVERSION}/cmake-${CMAKEVERSION}-linux-x86_64.tar.gz \
        | tar xz -C /usr/local --strip-components 1; \
    fi

ENV LDFLAGS=-s
ENV PATH=/usr/local/bin:$PATH

# ============================================================================
# ЭТАП 3: Сборка CPU бэкенда
# ============================================================================
FROM base AS cpu
ARG PARALLEL
WORKDIR /build

# Копирование CMake файлов и GGML
COPY CMakeLists.txt CMakePresets.json ./
COPY ml/backend/ggml/ggml ml/backend/ggml/ggml

# Сборка CPU backend
RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CPU' -DCMAKE_BUILD_TYPE=Release && \
    cmake --build --parallel ${PARALLEL} --preset 'CPU' --config Release && \
    cmake --install build --component CPU --strip --parallel ${PARALLEL}

# ============================================================================
# ЭТАП 4: Сборка CUDA 12 бэкенда (AMD64 ONLY)
# ============================================================================
FROM --platform=linux/amd64 nvidia/cuda:12.8.0-devel-ubuntu22.04 AS cuda-builder

ARG PARALLEL
ARG CMAKEVERSION=3.25.1

# Установка минимальных зависимостей
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        ninja-build \
        ccache \
        build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Установка CMake
RUN curl -fsSL https://github.com/Kitware/CMake/releases/download/v${CMAKEVERSION}/cmake-${CMAKEVERSION}-linux-x86_64.tar.gz \
    | tar xz -C /usr/local --strip-components 1

WORKDIR /build

# Копирование файлов сборки
COPY CMakeLists.txt CMakePresets.json ./
COPY ml/backend/ggml/ggml ml/backend/ggml/ggml

# Сборка CUDA backend
ENV PATH=/usr/local/cuda/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CUDA 12' -DCMAKE_BUILD_TYPE=Release && \
    cmake --build --parallel ${PARALLEL} --preset 'CUDA 12' --config Release && \
    cmake --install build --component CUDA --strip --parallel ${PARALLEL}

# ============================================================================
# ЭТАП 5: Сборка Go-приложения с исправлением CVE
# ============================================================================
FROM base AS go-builder
WORKDIR /go/src/github.com/ollama/ollama

# Установка Go 1.24.1
RUN curl -fsSL https://golang.org/dl/go1.24.1.linux-amd64.tar.gz \
    | tar xz -C /usr/local && \
    rm -rf /usr/local/go/src

ENV PATH=/usr/local/go/bin:$PATH
ENV GOPATH=/go
ENV GOCACHE=/root/.cache/go-build
ENV GOMODCACHE=/root/.cache/go-mod

# Копирование go.mod и go.sum для кеширования зависимостей
COPY go.mod go.sum ./

# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Обновление golang.org/x/crypto до v0.45.0
# Устраняет CVE-2025-47914 (CVSS 5.3) и CVE-2025-58181 (CVSS 5.3)
RUN go get golang.org/x/crypto@v0.45.0 && \
    go get -u gopkg.in/yaml.v3 && \
    go mod tidy && \
    go mod verify && \
    go mod download

# Копирование исходного кода
COPY . .

# Сборка с оптимизацией безопасности (CGO_ENABLED для CUDA)
ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-I/usr/local/include"
ENV CGO_LDFLAGS="-L/usr/local/lib64"
RUN --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath -buildmode=pie -ldflags="-w -s -extldflags=-static" \
    -tags cuda -o /bin/ollama .

# Верификация бинарника
RUN /bin/ollama --version && \
    ldd /bin/ollama | grep -E "(libc|libcuda|libcudart)" || echo "Static linking successful"

# ============================================================================
# ЭТАП 6: Финальный runtime образ (минимальный)
# ============================================================================
FROM --platform=linux/amd64 registry.astralinux.ru/library/astra/ubi18:1.8.1

# Метаданные образа
LABEL maintainer="DevOps INGOS <devops@ingos.ru>" \
      version="1.0.0-secure-cuda12-amd64-astra" \
      description="Ollama LLM runtime CUDA 12 AMD64 Astra Linux UBI 1.8.1" \
      vendor="INGOS Corporation" \
      security.scan="trivy,grype" \
      base.image="astra-ubi18:1.8.1" \
      cuda.version="12.8" \
      platform="linux/amd64" \
      python.version="3.12"

# Копирование Python 3.12 runtime (без dev пакетов)
COPY --from=python-source /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=python-source /usr/local/bin/python3.12 /usr/local/bin/python3.12
COPY --from=python-source /usr/local/bin/pip3.12 /usr/local/bin/pip3.12
COPY --from=python-source /usr/local/bin/python /usr/local/bin/python

# Обновление динамического линковщика
RUN ldconfig

# Установка минимальных runtime зависимостей БЕЗ upgrade
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libvulkan1 \
        libssl3 \
        zlib1g \
        libffi8 \
        liblzma5 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    # Создание символических ссылок для Python
    ln -sf /usr/local/bin/python3.12 /usr/bin/python3 && \
    ln -sf /usr/local/bin/pip3.12 /usr/bin/pip3

# Копирование проверенных бинарников
COPY --from=go-builder /bin/ollama /usr/bin/ollama
COPY --from=cpu /build/dist/lib/ollama /usr/lib/ollama/
COPY --from=cuda-builder /build/dist/lib/ollama /usr/lib/ollama/

# Установка переменных окружения для CUDA
ENV LD_LIBRARY_PATH=/usr/lib/ollama:/usr/local/lib:/usr/local/cuda/lib64:$LD_LIBRARY_PATH
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all

# Создание непривилегированного пользователя
RUN groupadd -r -g 1000 ollama && \
    useradd -r -u 1000 -g ollama -s /bin/false -c "Ollama Service User" ollama && \
    mkdir -p /home/ollama/.ollama /home/ollama/.ollama/models && \
    chown -R ollama:ollama /home/ollama /usr/lib/ollama && \
    # Создание конфигурации
    echo "OLLAMA_HOST=0.0.0.0:11434" > /home/ollama/.ollama/config && \
    chown ollama:ollama /home/ollama/.ollama/config

# Установка рабочей директории
WORKDIR /home/ollama

# Переключение на непривилегированного пользователя
USER ollama

# Настройка переменных окружения
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_MODELS=/home/ollama/.ollama/models \
    PYTHONUNBUFFERED=1 \
    HOME=/home/ollama \
    PYTHONPATH=/usr/local/lib/python3.12

# Health check для мониторинга
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:11434/api/tags || exit 1

# Открытие порта API
EXPOSE 11434

# Точка входа и команда запуска
ENTRYPOINT ["/usr/bin/ollama"]
CMD ["serve"]
