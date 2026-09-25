pipeline {
    agent any

    triggers {
        // Jenkins runs on localhost, so a real GitHub webhook can't reach it without
        // a public tunnel. Polling is the practical local equivalent: check GitHub
        // every 2 minutes and auto-build on new commits to main.
        pollSCM('H/2 * * * *')
    }

    environment {
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        IMAGE = "${DOCKERHUB_CREDENTIALS_USR}/devops-pipeline-app"
        TAG = "${env.BUILD_NUMBER}"
        // Local demo target: the "deploy" stage runs on this Jenkins agent itself,
        // the same way the GitHub Actions workflow's deploy job does, since no
        // deployment server is configured for this project.
        PORT = "5060"
        // Homebrew's Jenkins service runs with a minimal PATH that doesn't include
        // where Docker Desktop's CLI lives on macOS.
        PATH = "/usr/local/bin:/opt/homebrew/bin:${env.PATH}"
    }

    stages {
        stage('Test') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install -q -r app/requirements.txt pytest
                    pytest tests/
                '''
            }
        }

        stage('Build & Push') {
            steps {
                sh '''
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login -u "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker build -t $IMAGE:$TAG -t $IMAGE:latest .
                    docker push $IMAGE:$TAG
                    docker push $IMAGE:latest
                '''
            }
        }

        stage('Deploy (blue-green)') {
            steps {
                sh 'chmod +x scripts/*.sh'
                sh 'PORT=$PORT bash scripts/deploy.sh $IMAGE $TAG'
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }
        success {
            echo "Deployment successful: ${IMAGE}:${TAG} is live on port ${PORT}"
        }
        failure {
            echo "Pipeline failed. If the deploy stage failed after promotion, rollback.sh already ran automatically; otherwise the previous live version (if any) was never touched."
        }
    }
}
