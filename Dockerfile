# vim: filetype=dockerfile
# Ollama Secure Build - CUDA 12 + AMD64 only
# Устранение CVE-2025-47914, CVE-2025-58181, CVE-2024-41996, CVE-2025-5222

ARG PARALLEL=8
ARG CMAKEVERSION=3.31.2
ARG CUDA12VERSION=12.8

# ============================================================================
# ЭТАП 1: Установка Python 3.12 из официального образа
# ============================================================================
FROM python:3.12-slim-bookworm AS python-source

# ============================================================================
# ЭТАП 2: Базовая настройка Astra Linux с Python 3.12
# ============================================================================
FROM --platform=linux/amd64 registry.astralinux.ru/library/astra/ubi18:1.8.1 AS base

# Копирование Python 3.12 из официального образа
COPY --from=python-source /usr/local /usr/local

# Обновление динамического линковщика
RUN ldconfig

# Установка базовых зависимостей
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
        ccache && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Установка CMake
ARG CMAKEVERSION
RUN curl -fsSL https://github.com/Kitware/CMake/releases/download/v${CMAKEVERSION}/cmake-${CMAKEVERSION}-linux-x86_64.tar.gz \
    | tar xz -C /usr/local --strip-components 1

ENV LDFLAGS=-s

# ============================================================================
# ЭТАП 3: Сборка CPU бэкенда
# ============================================================================
FROM base AS cpu
ARG PARALLEL
WORKDIR /build

COPY CMakeLists.txt CMakePresets.json ./
COPY ml/backend/ggml/ggml ml/backend/ggml/ggml

RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CPU' && \
    cmake --build --parallel ${PARALLEL} --preset 'CPU' && \
    cmake --install build --component CPU --strip --parallel ${PARALLEL}

# ============================================================================
# ЭТАП 4: Сборка CUDA 12 бэкенда (AMD64 ONLY)
# ============================================================================
FROM --platform=linux/amd64 nvidia/cuda:12.8.0-devel-ubuntu22.04 AS cuda-builder

ARG PARALLEL
ARG CMAKEVERSION

# Установка зависимостей
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        cmake \
        ninja-build \
        gcc \
        g++ \
        ccache && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Установка CMake
RUN curl -fsSL https://github.com/Kitware/CMake/releases/download/v${CMAKEVERSION}/cmake-${CMAKEVERSION}-linux-x86_64.tar.gz \
    | tar xz -C /usr/local --strip-components 1

WORKDIR /build
COPY CMakeLists.txt CMakePresets.json ./
COPY ml/backend/ggml/ggml ml/backend/ggml/ggml

ENV PATH=/usr/local/cuda/bin:$PATH
RUN --mount=type=cache,target=/root/.ccache \
    cmake --preset 'CUDA 12' && \
    cmake --build --parallel ${PARALLEL} --preset 'CUDA 12' && \
    cmake --install build --component CUDA --strip --parallel ${PARALLEL}

# ============================================================================
# ЭТАП 5: Сборка Go-приложения с исправлением CVE
# ============================================================================
FROM base AS go-builder
WORKDIR /go/src/github.com/ollama/ollama

# Копирование go.mod и go.sum для кеширования зависимостей
COPY go.mod go.sum ./

# Установка Go 1.24.1
RUN curl -fsSL https://golang.org/dl/go$(awk '/^go/ { print $2 }' go.mod).linux-amd64.tar.gz \
    | tar xz -C /usr/local
ENV PATH=/usr/local/go/bin:$PATH

# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Обновление golang.org/x/crypto до v0.45.0
# Устраняет CVE-2025-47914 (CVSS 5.3) и CVE-2025-58181 (CVSS 5.3)
RUN go get golang.org/x/crypto@v0.45.0 && \
    go get -u gopkg.in/yaml.v3 && \
    go mod tidy && \
    go mod verify

# Загрузка остальных зависимостей
RUN go mod download

# Копирование исходного кода
COPY . .

# Сборка с оптимизацией безопасности
ENV CGO_ENABLED=1
RUN --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath -buildmode=pie -ldflags="-w -s" -o /bin/ollama .

# Верификация бинарника
RUN /bin/ollama --version

# ============================================================================
# ЭТАП 6: Сборка финального образа
# ============================================================================
FROM --platform=linux/amd64 registry.astralinux.ru/library/astra/ubi18:1.8.1

# Метаданные образа
LABEL maintainer="DevOps INGOS <devops@ingos.ru>" \
      version="1.0.0-secure-cuda12-amd64" \
      description="Ollama LLM runtime CUDA 12 AMD64 with security patches" \
      vendor="INGOS Corporation" \
      security.scan="trivy,grype" \
      base.image="astra-ubi18:1.8.1" \
      cuda.version="12.8" \
      platform="linux/amd64"

# Копирование Python 3.12
COPY --from=python-source /usr/local /usr/local
RUN ldconfig

# Обновление системных пакетов для устранения CVE-2024-41996, CVE-2025-5222
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libvulkan1 \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Копирование проверенных бинарников
COPY --from=go-builder /bin/ollama /usr/bin/ollama
COPY --from=cpu /build/dist/lib/ollama /usr/lib/ollama/
COPY --from=cuda-builder /build/dist/lib/ollama /usr/lib/ollama/

# Создание непривилегированного пользователя
RUN groupadd -r -g 1000 ollama && \
    useradd -r -u 1000 -g ollama -s /bin/false -c "Ollama Service User" ollama && \
    mkdir -p /home/ollama/.ollama && \
    chown -R ollama:ollama /home/ollama /usr/lib/ollama

# Установка рабочей директории
WORKDIR /home/ollama

# Переключение на непривилегированного пользователя
USER ollama

# Настройка переменных окружения
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/lib/ollama \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    NVIDIA_VISIBLE_DEVICES=all \
    OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_MODELS=/home/ollama/.ollama/models \
    PYTHONUNBUFFERED=1 \
    HOME=/home/ollama

# Health check для мониторинга
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:11434/api/tags || exit 1

# Открытие порта API
EXPOSE 11434

# Точка входа и команда запуска
ENTRYPOINT ["/usr/bin/ollama"]
CMD ["serve"]
