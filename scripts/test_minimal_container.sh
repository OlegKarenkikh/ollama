#!/bin/sh
#
# Скрипт для проверки работоспособности минимального контейнера Ollama
#

set -eu

IMAGE=${1:-"olegkarenkikh/ollama:minimal"}
CONTAINER_NAME="ollama-minimal-test"

echo "=========================================="
echo "Testing Minimal Container"
echo "=========================================="
echo "Image: ${IMAGE}"
echo "Container name: ${CONTAINER_NAME}"
echo ""

# Останавливаем и удаляем старый контейнер, если есть
sudo docker stop ${CONTAINER_NAME} 2>/dev/null || true
sudo docker rm ${CONTAINER_NAME} 2>/dev/null || true

echo "=== Pulling image ==="
sudo docker pull ${IMAGE}

echo ""
echo "=== Image information ==="
sudo docker images ${IMAGE} --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

echo ""
echo "=== Starting container ==="
sudo docker run -d \
    --name ${CONTAINER_NAME} \
    -p 11434:11434 \
    ${IMAGE}

echo ""
echo "=== Waiting for container to start ==="
sleep 5

echo ""
echo "=== Container status ==="
sudo docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Container logs (last 20 lines) ==="
sudo docker logs --tail 20 ${CONTAINER_NAME} 2>&1 || echo "No logs available"

echo ""
echo "=== Testing API endpoint ==="
sleep 3
curl -f http://localhost:11434/api/tags 2>&1 && echo "" && echo "✅ API endpoint is working!" || echo "❌ API endpoint test failed"

echo ""
echo "=== Testing version command ==="
sudo docker exec ${CONTAINER_NAME} /usr/bin/ollama --version 2>&1 && echo "✅ Version command works!" || echo "❌ Version command failed"

echo ""
echo "=== Container health check ==="
sudo docker inspect ${CONTAINER_NAME} --format='{{json .State.Health}}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "Health check info not available"

echo ""
echo "=== Stopping test container ==="
sudo docker stop ${CONTAINER_NAME}
sudo docker rm ${CONTAINER_NAME}

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="
