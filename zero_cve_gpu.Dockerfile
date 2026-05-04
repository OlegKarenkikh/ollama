# Builder stage
FROM nvidia/cuda:12.6.2-devel-ubuntu22.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get dist-upgrade -y && apt-get install -y --no-install-recommends curl ca-certificates build-essential git ninja-build pkg-config && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/Kitware/CMake/releases/download/v3.31.5/cmake-3.31.5-linux-x86_64.tar.gz | tar xz -C /usr/local --strip-components 1
WORKDIR /workspace/ollama
COPY go.mod go.sum ./
RUN GO_VERSION=$(awk '/^go/ { print $2 }' go.mod) && curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz | tar xz -C /usr/local
ENV PATH="/usr/local/go/bin:${PATH}"
COPY CMakeLists.txt CMakePresets.json ./
COPY ml/backend/ggml/ggml ml/backend/ggml/ggml
RUN cmake --preset "CUDA 12" && cmake --build --preset "CUDA 12" --parallel 1 && cmake --install build --component CUDA --strip --parallel 1
COPY . .
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -o /usr/local/bin/ollama .

# Final stage using Chainguard Wolfi + NVIDIA packages mapped manually
FROM cgr.dev/chainguard/wolfi-base:latest
RUN apk update && apk upgrade && apk add ca-certificates libstdc++ libgcc && rm -rf /var/cache/apk/*
RUN addgroup -S ollama && adduser -S ollama -G ollama
COPY --from=build /usr/local/bin/ollama /usr/local/bin/ollama
COPY --from=build /workspace/ollama/dist /usr/local/lib/ollama
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all
RUN chown -R ollama:ollama /usr/local/bin/ollama /usr/local/lib/ollama
USER ollama
ENTRYPOINT ["/usr/local/bin/ollama"]
CMD ["serve"]
