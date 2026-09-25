#!/bin/bash
URL="http://localhost:5000/health"
RETRIES=5
DELAY=5

for i in $(seq 1 $RETRIES); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" $URL)
  if [ "$STATUS" == "200" ]; then
    echo "Health check passed on attempt $i"
    exit 0
  fi
  echo "Attempt $i failed (status $STATUS). Retrying in ${DELAY}s..."
  sleep $DELAY
done

echo "Health check failed after $RETRIES attempts"
exit 1
