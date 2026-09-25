# Self-Healing Deployment Pipeline for a Containerized Web Application

A DevOps pipeline that automatically builds, tests, containerizes, and deploys a small web
application, with an automated health check that detects a failed deployment and triggers a
rollback to the previous working version.

## Architecture

```
Git push --> CI (build + test) --> Docker build/push --> Deploy --> Health check --> OK: done
                                                                                  \--> FAIL: rollback
```

## Tools used

- **Git / GitHub** — source control and trigger for the pipeline
- **GitHub Actions** — CI/CD orchestration
- **Docker** — containerization of the web application
- **Docker Hub** — container image registry
- **Flask** — minimal web application with a `/health` endpoint
- **pytest** — unit tests run in CI before building the image
- **Bash scripts** — deploy, health check, and rollback logic on the target host

## Project structure

```
app/                    Flask application
  app.py
  requirements.txt
tests/                  Unit tests
  test_app.py
scripts/                Deployment automation
  deploy.sh             Blue-green deploy: health-checks new version in staging before
                        promoting it to live; triggers rollback if promotion fails
  healthcheck.sh        Polls /health with retries (URL overridable via HEALTHCHECK_URL)
  rollback.sh           Redeploys the last known-good image tag
.github/workflows/
  ci-cd.yml             GitHub Actions pipeline: test -> build & push -> deploy
Dockerfile
docker-compose.yml      For local build/run
```

## How the pipeline works

1. A push to `main` triggers the GitHub Actions workflow.
2. **build-and-test**: installs dependencies and runs `pytest` against the Flask app.
3. **build-and-push-image**: builds the Docker image, tags it with both the Git commit SHA
   and `latest`, and pushes both tags to Docker Hub.
4. **deploy**: runs `scripts/deploy.sh` (on the GitHub Actions runner itself, since no
   deployment server is configured for this project — see note below), which does a
   **blue-green swap**:
   - pulls the new image and starts it as a *staging* container on a side port
     (`PORT+1`), without touching the live container
   - runs `scripts/healthcheck.sh` against the staging container
   - if staging fails its health check, it's discarded and the live container — if any —
     is never touched, so there is no downtime and nothing to roll back
   - if staging is healthy, the current live image tag is recorded as "last good", the old
     live container is replaced with the new one on the live port, and it's health-checked
     again post-promotion
   - if that final check fails, `scripts/rollback.sh` redeploys the last good tag and
     re-verifies health

> **Note on the deploy target:** the `deploy` job runs the scripts locally on the GitHub
> Actions runner rather than over SSH to a real server, since each workflow run gets a fresh
> runner (so `last_good_tag.txt` does not persist between separate CI runs — that's expected).
> To point this at a real server later, swap the `deploy` step back to an `appleboy/ssh-action`
> step that calls the same `scripts/deploy.sh` on the remote host — the scripts themselves
> don't change. See "Demonstrating self-healing (rollback) locally" below for a full,
> repeatable rollback demo that doesn't depend on CI runner state.

## Local setup and testing (no server required)

```bash
# Run unit tests
pip install -r app/requirements.txt pytest
pytest tests/

# Build and run the container
docker compose up --build

# In another terminal, verify the health endpoint
curl http://localhost:5000/health
```

## One-time GitHub setup for the full CI/CD pipeline

1. Push this project to a new GitHub repository.
2. Add these repository secrets (Settings -> Secrets and variables -> Actions):
   - `DOCKERHUB_USERNAME`
   - `DOCKERHUB_TOKEN` (Docker Hub access token)
3. Push a commit to `main` and watch the pipeline run in the Actions tab.

If you later have a real deployment server, add `DEPLOY_HOST`, `DEPLOY_USER`, and
`DEPLOY_SSH_KEY` secrets, copy `scripts/` to `/home/<DEPLOY_USER>/scripts/` on that host, and
swap the `deploy` job's step back to an `appleboy/ssh-action` step that calls
`scripts/deploy.sh` remotely.

## Demonstrating self-healing (blue-green + rollback) locally

This reproduces the deploy -> staging health-check -> promote/discard flow on your own
machine using plain Docker, independent of any single CI run (CI runners are ephemeral, so
this is the most reliable way to demo it). `PORT` defaults to `5000`; set it to any free port
(the example below uses `5050` since macOS's AirPlay Receiver often squats on 5000):

```bash
IMAGE=devops-pipeline-demo
export PORT=5050

# 1. Build and deploy a healthy v1 (starts in staging on PORT+1, then promotes to PORT)
docker build -t $IMAGE:v1 --build-arg APP_VERSION=v1 .
bash scripts/deploy.sh $IMAGE v1
curl http://localhost:$PORT/health   # -> {"status": "healthy"}

# 2. Break the health endpoint and build a broken v2
#    (e.g. edit app/app.py so /health returns a 500, or raises on startup)
docker build -t $IMAGE:v2 --build-arg APP_VERSION=v2 .
bash scripts/deploy.sh $IMAGE v2
# -> staging health check fails, v2 is discarded, and the live v1 container is
#    never stopped or replaced — zero downtime, no rollback needed

# 3. Confirm v1 is still live and was never interrupted
docker ps --filter name=web-app
curl http://localhost:$PORT/           # version field still reads "v1"
curl http://localhost:$PORT/health     # -> {"status": "healthy"}
```

`deploy.sh` only touches the live container after the new version has already proven itself
healthy in staging. `rollback.sh` (which redeploys the tag recorded in
`scripts/last_good_tag.txt`) only runs automatically in the rarer case where a newly-promoted
live container fails its own post-promotion health check.
