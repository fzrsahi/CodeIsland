#!/usr/bin/env bash
# ==============================================================================
# Setup Local Woodpecker Linux Docker Runner on Host
# Connects to AWS EC2 Woodpecker Server via local tunnel (localhost:9090)
#
# Usage:
#   ./scripts/setup-linux-runner.sh           # Run or restart the runner
#   ./scripts/setup-linux-runner.sh --dry-run # Print configuration and docker command
#   ./scripts/setup-linux-runner.sh --status  # Check status and recent logs
#   ./scripts/setup-linux-runner.sh --stop    # Stop runner container
# ==============================================================================
set -euo pipefail

RUNNER_NAME="morrow-linux-runner"
AGENT_IMAGE="woodpeckerci/woodpecker-agent:v2.8.3"
AGENT_SECRET="${WOODPECKER_AGENT_SECRET:-7111f4ee4bafc2ef5d47ee473608f47ea3a772e8c2f543e548d474eaa23ea6a5}"
SERVER_GRPC="${WOODPECKER_SERVER:-host.docker.internal:9090}"
MAX_WORKFLOWS="${WOODPECKER_MAX_WORKFLOWS:-1}"
FILTER_LABELS="${WOODPECKER_FILTER_LABELS:-platform=linux/amd64,backend=docker}"
HOSTNAME_ID="${WOODPECKER_HOSTNAME:-debian-ryzen-host}"

ACTION="${1:-start}"

if [ "$ACTION" = "--dry-run" ]; then
    echo "==> Woodpecker Linux Runner Configuration (Dry-Run):"
    echo "  Container:     $RUNNER_NAME"
    echo "  Image:         $AGENT_IMAGE"
    echo "  gRPC Server:   $SERVER_GRPC"
    echo "  Max Workflows: $MAX_WORKFLOWS"
    echo "  Labels:        $FILTER_LABELS"
    echo "  Hostname:      $HOSTNAME_ID"
    echo ""
    echo "Docker Execution Command:"
    cat <<EOF
docker run -d \\
  --name "$RUNNER_NAME" \\
  --restart always \\
  --add-host=host.docker.internal:host-gateway \\
  -v /var/run/docker.sock:/var/run/docker.sock \\
  -e WOODPECKER_SERVER="$SERVER_GRPC" \\
  -e WOODPECKER_AGENT_SECRET="***" \\
  -e WOODPECKER_MAX_WORKFLOWS=$MAX_WORKFLOWS \\
  -e WOODPECKER_FILTER_LABELS="$FILTER_LABELS" \\
  -e WOODPECKER_HOSTNAME="$HOSTNAME_ID" \\
  $AGENT_IMAGE
EOF
    exit 0
fi

if [ "$ACTION" = "--status" ]; then
    echo "==> Checking runner status: $RUNNER_NAME"
    if docker ps -a --filter "name=^/${RUNNER_NAME}$" --format '{{.Names}}' | grep -q "^${RUNNER_NAME}$"; then
        docker ps --filter "name=^/${RUNNER_NAME}$"
        echo ""
        echo "==> Recent Logs:"
        docker logs --tail 20 "$RUNNER_NAME" || true
    else
        echo "Runner container '$RUNNER_NAME' does not exist."
    fi
    exit 0
fi

if [ "$ACTION" = "--stop" ]; then
    echo "==> Stopping runner container: $RUNNER_NAME"
    docker stop "$RUNNER_NAME" 2>/dev/null || true
    docker rm "$RUNNER_NAME" 2>/dev/null || true
    echo "Runner stopped."
    exit 0
fi

echo "==> Configuring Woodpecker Linux Docker Runner..."

# Ensure Docker daemon is running
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running!"; exit 1; }

# Remove existing container if present
if docker ps -a --filter "name=^/${RUNNER_NAME}$" --format '{{.Names}}' | grep -q "^${RUNNER_NAME}$"; then
    echo "==> Removing existing runner container..."
    docker rm -f "$RUNNER_NAME" >/dev/null 2>&1 || true
fi

# Run Woodpecker Agent with strict concurrency limits to protect 16 GB host RAM
echo "==> Spawning $RUNNER_NAME container..."
docker run -d \
  --name "$RUNNER_NAME" \
  --restart always \
  --add-host=host.docker.internal:host-gateway \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e WOODPECKER_SERVER="$SERVER_GRPC" \
  -e WOODPECKER_AGENT_SECRET="$AGENT_SECRET" \
  -e WOODPECKER_MAX_WORKFLOWS="$MAX_WORKFLOWS" \
  -e WOODPECKER_FILTER_LABELS="$FILTER_LABELS" \
  -e WOODPECKER_HOSTNAME="$HOSTNAME_ID" \
  "$AGENT_IMAGE"

echo "✅ Woodpecker Linux Runner started successfully!"
docker ps --filter "name=^/${RUNNER_NAME}$"
