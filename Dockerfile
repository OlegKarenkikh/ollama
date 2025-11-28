# vim: filetype=dockerfile
# Ollama Secure Build - CUDA 12 + AMD64 only (Astra Linux UBI 1.8.1)
# Устраняет CVE-2025-47914, CVE-2025-58181, CVE-2024-41996, CVE-2025-5222

ARG PARALLEL=8
ARG CMAKEVERSION=3.25.1
ARG CUDA12VERSION=12.8

# ============================================================================
# ЭТАП 1: Источник Python 3.12
# ============================================================================
FROM python:3.12-slim-bookworm AS python-source

# ============================================================================
# ЭТАП 2: База Astra Linux UBI 1.8.1 + toolchain
# ============================================================================
FROM registry.astralinux.ru/library/astra/ubi18:1.8.1 AS base

# Копируем Python 3.12 из python-образа
COPY --from=python-source /usr/local /usr/local
RUN ldconfig

# Устанавливаем build-зависимости БЕЗ apt-get upgrade (в Astra UBI он запрещён)
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

# Если cmake не установлен из пакета — ставим бинарник нужной версии
ARG CMAKEVERSION
RUN if ! command -v cmake >/dev/null 2>&1; then \
        curl -fsSL https://github.com/Kitware/CMake/releases/download/v${CMAKEVERSION}/cmake-${CMAKEVERSION}-linux-x86_64.tar.gz \
        | tar xz -C /usr/local --strip-components 1; \
    fi

ENV LDFLAGS=-s
ENV PATH=/usr/local/bin:$PATH

# ============================================================================
# ЭТАП 3: CPU backend (fallback)
# ============================================================================
FROM base AS cpu
ARG PARALLEL
WORKDIR /build

COPY CMakeLists.txt CMakePresets.json ./
COPY ml/backend/ggml/ggml ml/backend/ggml/ggml

RUN cmake --preset 'CPU' -DCMAKE_BUILD_TYPE=Release && \
    cmake --build --preset 'CPU' --config Release && \
    cmake --install build --component CPU --strip

# ============================================================================
# ЭТАП 4: CUDA 12 backend (отдельный builder на nvidia/cuda)
# ============================================================================
FROM nvidia/cuda:12.8.0-devel-ubuntu22.04 AS cuda-builder

ARG PARALLEL
ARG CMAKEVERSION=3.25.1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        ninja-build \
        ccache \
        build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://github.com/Kitware/CMake/releases/download/v${CMAKEVERSION}/cmake-${CMAKEVERSION}-linux-x86_64.tar.gz \
    | tar xz -C /usr/local --strip-components 1

WORKDIR /build

COPY CMakeLists.txt CMakePresets.json ./
COPY ml/backend/ggml/ggml ml/backend/ggml/ggml

ENV PATH=/usr/local/cuda/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

RUN cmake --preset 'CUDA 12' -DCMAKE_BUILD_TYPE=Release && \
    cmake --build --parallel ${PARALLEL} --preset 'CUDA 12' --config Release && \
    cmake --install build --component CUDA --strip --parallel ${PARALLEL}

# ============================================================================
# ЭТАП 5: Go-приложение с исправлением CVE
# ============================================================================
FROM base AS go-builder
WORKDIR /go/src/github.com/ollama/ollama

# Установка ПОЛНОГО Go 1.24.1 (c stdlib, без удаления src)
RUN curl -fsSL https://golang.org/dl/go1.24.1.linux-amd64.tar.gz \
    | tar xz -C /usr/local

ENV PATH=/usr/local/go/bin:$PATH
ENV GOPATH=/go
ENV GOCACHE=/root/.cache/go-build
ENV GOMODCACHE=/root/.cache/go-mod

# go.mod и go.sum для кеша
COPY go.mod go.sum ./

# Обновляем golang.org/x/crypto и yaml.v3, затем чистим зависимости
RUN go env -w GOPROXY=https://proxy.golang.org,direct && \
    go get golang.org/x/crypto@v0.45.0 gopkg.in/yaml.v3@v3.0.1 && \
    go mod tidy && \
    go mod verify && \
    go mod download

# Остальной исходный код
COPY . .

# Сборка ollama с CGO и безопасными флагами
ENV CGO_ENABLED=1
RUN go build -trimpath -buildmode=pie -ldflags="-w -s" -o /bin/ollama .

# Быстрая проверка
RUN /bin/ollama --version

# ============================================================================
# ЭТАП 6: Финальный runtime Astra UBI 1.8.1
# ============================================================================
FROM registry.astralinux.ru/library/astra/ubi18:1.8.1

LABEL maintainer="DevOps INGOS <devops@ingos.ru>" \
      version="1.0.0-secure-cuda12-amd64-astra" \
      description="Ollama LLM runtime CUDA 12 AMD64 Astra Linux UBI 1.8.1" \
      vendor="INGOS Corporation" \
      security.scan="trivy,grype" \
      base.image="astra-ubi18:1.8.1" \
      cuda.version="12.8" \
      platform="linux/amd64" \
      python.version="3.12"

# Минимальный runtime Python 3.12
COPY --from=python-source /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=python-source /usr/local/bin/python3.12 /usr/local/bin/python3.12
COPY --from=python-source /usr/local/bin/pip3.12 /usr/local/bin/pip3.12
COPY --from=python-source /usr/local/bin/python /usr/local/bin/python

RUN ldconfig

# Минимальные runtime-зависимости (без upgrade)
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
    ln -sf /usr/local/bin/python3.12 /usr/bin/python3 && \
    ln -sf /usr/local/bin/pip3.12 /usr/bin/pip3

# Копируем бинарники и библиотеки
COPY --from=go-builder /bin/ollama /usr/bin/ollama
COPY --from=cpu /build/dist/lib/ollama /usr/lib/ollama/
COPY --from=cuda-builder /build/dist/lib/ollama /usr/lib/ollama/

# CUDA env
ENV LD_LIBRARY_PATH=/usr/lib/ollama:/usr/local/lib:/usr/local/cuda/lib64:$LD_LIBRARY_PATH
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all

# Непривилегированный пользователь
RUN groupadd -r -g 1000 ollama && \
    useradd -r -u 1000 -g ollama -s /bin/false -c "Ollama Service User" ollama && \
    mkdir -p /home/ollama/.ollama /home/ollama/.ollama/models && \
    chown -R ollama:ollama /home/ollama /usr/lib/ollama && \
    echo "OLLAMA_HOST=0.0.0.0:11434" > /home/ollama/.ollama/config && \
    chown ollama:ollama /home/ollama/.ollama/config

WORKDIR /home/ollama
USER ollama

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_MODELS=/home/ollama/.ollama/models \
    PYTHONUNBUFFERED=1 \
    HOME=/home/ollama \
    PYTHONPATH=/usr/local/lib/python3.12

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:11434/api/tags || exit 1

EXPOSE 11434

ENTRYPOINT ["/usr/bin/ollama"]
CMD ["serve"]
