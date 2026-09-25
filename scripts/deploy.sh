#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE=$1
NEW_TAG=$2
PORT=${PORT:-5000}
STAGING_PORT=$((PORT + 1))
LAST_GOOD_FILE="$SCRIPT_DIR/last_good_tag.txt"
CONTAINER_NAME=web-app
STAGING_NAME=web-app-staging

echo "Pulling new image: $IMAGE:$NEW_TAG"
docker pull "$IMAGE:$NEW_TAG" || echo "Pull failed, falling back to local image if present"

echo "Starting new version in staging on port $STAGING_PORT (not yet receiving live traffic)"
docker rm -f "$STAGING_NAME" >/dev/null 2>&1 || true
docker run -d --name "$STAGING_NAME" -p "$STAGING_PORT:5000" "$IMAGE:$NEW_TAG"

echo "Health-checking staging container"
if HEALTHCHECK_URL="http://localhost:$STAGING_PORT/health" bash "$SCRIPT_DIR/healthcheck.sh"; then
  echo "Staging is healthy. Promoting to live."

  LIVE_EXISTS=false
  if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    LIVE_EXISTS=true
    CURRENT_TAG=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME" | cut -d':' -f2)
    echo "$CURRENT_TAG" > "$LAST_GOOD_FILE"
  fi

  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$STAGING_NAME"
  docker run -d --name "$CONTAINER_NAME" -p "$PORT:5000" "$IMAGE:$NEW_TAG"

  echo "Verifying promoted live container"
  if HEALTHCHECK_URL="http://localhost:$PORT/health" bash "$SCRIPT_DIR/healthcheck.sh"; then
    echo "Deployment successful."
  elif [ "$LIVE_EXISTS" = true ]; then
    echo "Live container failed its post-promotion health check. Rolling back..."
    bash "$SCRIPT_DIR/rollback.sh" "$IMAGE"
    exit 1
  else
    echo "Initial deployment failed its post-promotion health check. No previous version exists to roll back to."
    exit 1
  fi
else
  echo "Staging health check failed. Discarding this version."
  docker rm -f "$STAGING_NAME" >/dev/null 2>&1 || true
  if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Live container was never touched and is still serving traffic on port $PORT."
  else
    echo "No live container exists and staging failed. Nothing is currently deployed."
  fi
  exit 1
fi
