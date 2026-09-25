FROM jenkins/jenkins:lts

USER root

# Docker CLI (so Jenkins can build/run/push images against the host's Docker daemon
# via the mounted socket) and Python (to run the app's pytest suite).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      docker.io \
      python3 \
      python3-pip \
      python3-venv \
      curl && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -f docker && usermod -aG docker jenkins

# Stays as root at runtime (set via docker-compose) so it can always read/write the
# host's docker.sock, regardless of that socket's GID on the host (varies with Docker
# Desktop on macOS).
