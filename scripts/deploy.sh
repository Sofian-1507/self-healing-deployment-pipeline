#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE=$1
NEW_TAG=$2
LAST_GOOD_FILE="$SCRIPT_DIR/last_good_tag.txt"
CONTAINER_NAME=web-app

# Save current running tag as "previous" before deploying new one
if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
  CURRENT_TAG=$(docker inspect --format='{{.Config.Image}}' $CONTAINER_NAME | cut -d':' -f2)
  echo "$CURRENT_TAG" > "$LAST_GOOD_FILE"
fi

echo "Pulling new image: $IMAGE:$NEW_TAG"
docker pull "$IMAGE:$NEW_TAG" || echo "Pull failed, falling back to local image if present"

echo "Stopping old container (if any)"
docker rm -f $CONTAINER_NAME || true

echo "Starting new container"
docker run -d --name $CONTAINER_NAME -p 5000:5000 "$IMAGE:$NEW_TAG"

echo "Running health check"
if bash "$SCRIPT_DIR/healthcheck.sh"; then
  echo "Deployment successful."
else
  echo "Health check failed. Rolling back..."
  bash "$SCRIPT_DIR/rollback.sh" "$IMAGE"
  exit 1
fi
