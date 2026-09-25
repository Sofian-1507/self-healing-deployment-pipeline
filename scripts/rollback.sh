#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE=$1
PORT=${PORT:-5000}
LAST_GOOD_FILE="$SCRIPT_DIR/last_good_tag.txt"
CONTAINER_NAME=web-app
STAGING_NAME=web-app-staging

if [ ! -f "$LAST_GOOD_FILE" ]; then
  echo "No previous good version recorded. Cannot roll back."
  exit 1
fi

PREV_TAG=$(cat "$LAST_GOOD_FILE")
echo "Rolling back to previous version: $PREV_TAG"

docker rm -f "$STAGING_NAME" >/dev/null 2>&1 || true
docker rm -f "$CONTAINER_NAME" || true
docker pull "$IMAGE:$PREV_TAG" || echo "Pull failed, falling back to local image if present"
docker run -d --name "$CONTAINER_NAME" -p "$PORT:5000" "$IMAGE:$PREV_TAG"

echo "Rollback complete. Verifying health..."
HEALTHCHECK_URL="http://localhost:$PORT/health" bash "$SCRIPT_DIR/healthcheck.sh"
