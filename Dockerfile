# Builder stage
FROM ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get dist-upgrade -y && apt-get install -y --no-install-recommends curl ca-certificates build-essential git && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/Kitware/CMake/releases/download/v3.31.5/cmake-3.31.5-linux-x86_64.tar.gz | tar xz -C /usr/local --strip-components 1
WORKDIR /workspace/ollama
COPY go.mod go.sum ./
RUN GO_VERSION=$(awk '/^go/ { print $2 }' go.mod) && curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz | tar xz -C /usr/local
ENV PATH="/usr/local/go/bin:${PATH}"
COPY CMakeLists.txt CMakePresets.json ./
COPY ml/backend/ggml/ggml/ ml/backend/ggml/ggml/
RUN cmake --preset "CPU" && cmake --build --preset "CPU" --parallel 1 && cmake --install build --component CPU --strip --parallel 1
COPY . .
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -o /usr/local/bin/ollama .

# Final stage using distroless
FROM cgr.dev/chainguard/wolfi-base:latest
RUN apk update && apk upgrade && apk add --no-cache ca-certificates libstdc++ libgcc && rm -rf /var/cache/apk/*
RUN addgroup -S ollama && adduser -S ollama -G ollama
COPY --from=build /usr/local/bin/ollama /usr/local/bin/ollama
COPY --from=build /workspace/ollama/dist/ /usr/local/lib/ollama/
RUN chown -R ollama:ollama /usr/local/bin/ollama /usr/local/lib/ollama
USER ollama
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/usr/local/bin/ollama", "list"]
ENTRYPOINT ["/usr/local/bin/ollama"]
CMD ["serve"]
