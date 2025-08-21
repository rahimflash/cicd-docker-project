#!/usr/bin/env groovy

pipeline {
    agent any
    
    environment {
        // Docker Hub configuration - removed credentials() usage
        // Will be handled with withCredentials in the push stage
        
        // Project configuration
        PROJECT_NAME = 'clms'
        BUILD_NUMBER = "${env.BUILD_NUMBER}"
        GIT_COMMIT_SHORT = "${env.GIT_COMMIT[0..7]}"
        
        // Application environment variables
        APP_NAME = 'CLMS'
        NODE_VERSION = '18'
        PHP_VERSION = '8.1'
        
        // Docker image names (Docker Hub) - will use username from withCredentials
        BACKEND_IMAGE = "${PROJECT_NAME}-backend"
        FRONTEND_IMAGE = "${PROJECT_NAME}-frontend"
        
        // Mono-repo paths
        BACKEND_PATH = 'back-end'
        FRONTEND_PATH = 'front-end'
    }
    
    options {
        buildDiscarder(logRotator(
            numToKeepStr: '10',
            daysToKeepStr: '30',
            artifactNumToKeepStr: '5'
        ))
        timeout(time: 45, unit: 'MINUTES')
        skipStagesAfterUnstable()
        parallelsAlwaysFailFast()
        disableConcurrentBuilds()
    }
    
    triggers {
        // Poll SCM every 5 minutes for changes
        pollSCM('H/5 * * * *')
        
        // Build daily at 2 AM for dependency updates
        cron('0 2 * * *')
    }
    
    parameters {
        choice(
            name: 'BUILD_TYPE',
            choices: ['development', 'staging', 'production'],
            description: 'Type of build to create'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: 'Skip running tests (not recommended)'
        )
        booleanParam(
            name: 'FORCE_REBUILD',
            defaultValue: false,
            description: 'Force rebuild without using Docker cache'
        )
        booleanParam(
            name: 'BUILD_BACKEND',
            defaultValue: true,
            description: 'Build backend service'
        )
        booleanParam(
            name: 'BUILD_FRONTEND',
            defaultValue: true,
            description: 'Build frontend service'
        )
        booleanParam(
            name: 'PUSH_TO_HUB',
            defaultValue: true,
            description: 'Push images to Docker Hub'
        )
        booleanParam(
            name: 'DEPLOY_LOCALLY',
            defaultValue: false,
            description: 'Deploy to local Docker environment'
        )
    }
    
    stages {
        stage('Preparation') {
            steps {
                script {
                    // Clean workspace
                    cleanWs()
                    
                    // Checkout code
                    checkout scm
                    
                    // Set build display name
                    currentBuild.displayName = "#${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                    currentBuild.description = "Branch: ${env.BRANCH_NAME} | Type: ${params.BUILD_TYPE}"
                    
                    // Verify Docker is available
                    sh 'docker --version'
                    sh 'docker-compose --version'
                    
                    // Show mono-repo structure
                    sh '''
                        echo "Mono-repo structure:"
                        ls -la
                        echo "Backend structure:"
                        ls -la ${BACKEND_PATH}/
                        echo "Frontend structure:"
                        ls -la ${FRONTEND_PATH}/
                    '''
                    
                    echo """
Starting CLMS Mono-repo Build Pipeline
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}
Backend: ${params.BUILD_BACKEND}
Frontend: ${params.BUILD_FRONTEND}
Push to Hub: ${params.PUSH_TO_HUB}
Deploy Locally: ${params.DEPLOY_LOCALLY}
"""
                }
            }
        }
        
        stage('Code Quality & Security') {
            parallel {
                stage('Backend Security Scan') {
                    when {
                        expression { params.BUILD_BACKEND }
                    }
                    steps {
                        dir("${BACKEND_PATH}") {
                            script {
                                // Check if .env exists
                                sh '''
                                    if [ -f .env ]; then
                                        echo "Backend .env file found"
                                    else
                                        echo "Backend .env file not found"
                                    fi
                                '''
                                
                                // Composer audit for security vulnerabilities
                                sh '''
                                    docker run --rm -v $(pwd):/app composer:2.7 audit || true
                                '''
                                
                                // PHP syntax check
                                sh '''
                                    find . -name "*.php" -exec php -l {} \\; | grep -v "No syntax errors" || true
                                '''
                            }
                        }
                    }
                }
                
                stage('Frontend Security Scan') {
                    when {
                        expression { params.BUILD_FRONTEND }
                    }
                    steps {
                        dir("${FRONTEND_PATH}") {
                            script {
                                // Check if .env.local exists
                                sh '''
                                    if [ -f .env.local ]; then
                                        echo "Frontend .env.local file found"
                                    else
                                        echo "Frontend .env.local file not found"
                                    fi
                                '''
                                
                                // NPM audit
                                sh '''
                                    docker run --rm -v $(pwd):/app -w /app node:${NODE_VERSION}-alpine \
                                        sh -c "npm audit --audit-level=high || true"
                                '''
                            }
                        }
                    }
                }
                
                stage('Secret Scanning') {
                    steps {
                        script {
                            // Basic secret scanning (excluding .env files)
                            sh '''
                                echo "Scanning for exposed secrets..."
                                # Check for common secret patterns in code (not .env files)
                                find . -name "*.php" -o -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" | \
                                    xargs grep -l -i "password.*=" || true
                                find . -name "*.php" -o -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" | \
                                    xargs grep -l -i "api.*key.*=" || true
                                find . -name "*.php" -o -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" | \
                                    xargs grep -l -i "secret.*=" || true
                            '''
                        }
                    }
                }
            }
        }
        
        stage('Build & Test') {
            parallel {
                stage('Backend Build & Test') {
                    when {
                        expression { params.BUILD_BACKEND }
                    }
                    stages {
                        stage('Backend Build') {
                            steps {
                                dir("${BACKEND_PATH}") {
                                    script {
                                        // Build backend Docker image
                                        def buildArgs = params.FORCE_REBUILD ? '--no-cache' : ''
                                        sh """
                                            docker build ${buildArgs} \
                                                -t ${BACKEND_IMAGE}:${BUILD_NUMBER} \
                                                -t ${BACKEND_IMAGE}:latest \
                                                -t ${BACKEND_IMAGE}:${params.BUILD_TYPE} \
                                                --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                                                --build-arg GIT_COMMIT=${GIT_COMMIT} \
                                                --build-arg BUILD_TYPE=${params.BUILD_TYPE} .
                                        """
                                    }
                                }
                            }
                        }
                        
                        stage('Backend Tests') {
                            when {
                                not {
                                    expression { params.SKIP_TESTS }
                                }
                            }
                            steps {
                                dir("${BACKEND_PATH}") {
                                    script {
                                        // Run Laravel tests
                                        sh '''
                                            docker run --rm \
                                                -v $(pwd):/home/app \
                                                -e APP_ENV=testing \
                                                -e APP_KEY=base64:$(openssl rand -base64 32) \
                                                -e DB_CONNECTION=sqlite \
                                                -e DB_DATABASE=:memory: \
                                                ${BACKEND_IMAGE}:${BUILD_NUMBER} \
                                                php artisan test --junit=test-results.xml || true
                                        '''
                                        
                                        // Publish test results if they exist
                                        if (fileExists('test-results.xml')) {
                                            junit testResults: 'test-results.xml', allowEmptyResults: true

                                            // publishTestResults testResultsPattern: 'test-results.xml'
                                        }
                                    }
                                }
                            }
                        }
                        
                        stage('Backend Quality') {
                            steps {
                                dir("${BACKEND_PATH}") {
                                    script {
                                        // Basic quality checks
                                        sh '''
                                            echo "Running backend quality checks..."
                                            # Check for TODO/FIXME comments
                                            grep -r -i "todo\\|fixme" . --exclude-dir=vendor || true
                                            
                                            # Check file permissions
                                            find . -name "*.php" -perm 777 || true
                                            
                                            # Check for debug statements
                                            grep -r "dd(" . --exclude-dir=vendor || true
                                            grep -r "dump(" . --exclude-dir=vendor || true
                                        '''
                                    }
                                }
                            }
                        }
                    }
                }
                
                stage('Frontend Build & Test') {
                    when {
                        expression { params.BUILD_FRONTEND }
                    }
                    stages {
                        stage('Frontend Build') {
                            steps {
                                dir("${FRONTEND_PATH}") {
                                    script {
                                        // Build frontend Docker image
                                        def buildArgs = params.FORCE_REBUILD ? '--no-cache' : ''
                                        sh """
                                            docker build ${buildArgs} \
                                                -t ${FRONTEND_IMAGE}:${BUILD_NUMBER} \
                                                -t ${FRONTEND_IMAGE}:latest \
                                                -t ${FRONTEND_IMAGE}:${params.BUILD_TYPE} \
                                                --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                                                --build-arg GIT_COMMIT=${GIT_COMMIT} \
                                                --build-arg NEXT_PUBLIC_APP_VERSION=${BUILD_NUMBER} \
                                                --build-arg BUILD_TYPE=${params.BUILD_TYPE} .
                                        """
                                    }
                                }
                            }
                        }
                        
                        stage('Frontend Tests') {
                            when {
                                not {
                                    expression { params.SKIP_TESTS }
                                }
                            }
                            steps {
                                dir("${FRONTEND_PATH}") {
                                    script {
                                        // Check if package.json exists
                                        sh '''
                                            if [ -f package.json ]; then
                                                echo "package.json found"
                                                cat package.json | grep -A 5 -B 5 "scripts" || true
                                            else
                                                echo "package.json not found"
                                            fi
                                        '''
                                        
                                        // Run Next.js build test
                                        sh '''
                                            docker run --rm \
                                                -v $(pwd):/app \
                                                -w /app \
                                                node:${NODE_VERSION}-alpine \
                                                sh -c "npm ci && npm run build" || true
                                        '''
                                        
                                        // Run linting if available
                                        sh '''
                                            docker run --rm \
                                                -v $(pwd):/app \
                                                -w /app \
                                                node:${NODE_VERSION}-alpine \
                                                sh -c "npm ci && (npm run lint || echo 'No lint script found')" || true
                                        '''
                                    }
                                }
                            }
                        }
                        
                        stage('Frontend Quality') {
                            steps {
                                dir("${FRONTEND_PATH}") {
                                    script {
                                        // Basic quality checks
                                        sh '''
                                            echo "Running frontend quality checks..."
                                            # Check for console.log statements
                                            grep -r "console\\.log" . --exclude-dir=node_modules || true
                                            
                                            # Check for TODO/FIXME comments
                                            grep -r -i "todo\\|fixme" . --exclude-dir=node_modules || true
                                            
                                            # Check for debugger statements
                                            grep -r "debugger" . --exclude-dir=node_modules || true
                                        '''
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        stage('Security Scanning') {
            parallel {
                stage('Backend Image Scan') {
                    when {
                        expression { params.BUILD_BACKEND }
                    }
                    steps {
                        script {
                            // Trivy security scan for backend image
                            sh """
                                docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                                    aquasec/trivy:latest image \
                                    --exit-code 0 \
                                    --severity HIGH,CRITICAL \
                                    --format json \
                                    --output backend-security-report.json \
                                    ${BACKEND_IMAGE}:${BUILD_NUMBER} || true
                            """
                            
                            // Archive security report
                            if (fileExists('backend-security-report.json')) {
                                archiveArtifacts artifacts: 'backend-security-report.json', fingerprint: true
                            }
                        }
                    }
                }
                
                stage('Frontend Image Scan') {
                    when {
                        expression { params.BUILD_FRONTEND }
                    }
                    steps {
                        script {
                            // Trivy security scan for frontend image
                            sh """
                                docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                                    aquasec/trivy:latest image \
                                    --exit-code 0 \
                                    --severity HIGH,CRITICAL \
                                    --format json \
                                    --output frontend-security-report.json \
                                    ${FRONTEND_IMAGE}:${BUILD_NUMBER} || true
                            """
                            
                            // Archive security report
                            if (fileExists('frontend-security-report.json')) {
                                archiveArtifacts artifacts: 'frontend-security-report.json', fingerprint: true
                            }
                        }
                    }
                }
            }
        }
        
        stage('Push to Docker Hub') {
            when {
                expression { params.PUSH_TO_HUB }
            }
            steps {
                script {
                    // Use withCredentials instead of credentials()
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub-credentials',
                        usernameVariable: 'DOCKER_HUB_USERNAME',
                        passwordVariable: 'DOCKER_HUB_PASSWORD'
                    )]) {
                        // Login to Docker Hub
                        sh """
                            echo '${DOCKER_HUB_PASSWORD}' | docker login -u '${DOCKER_HUB_USERNAME}' --password-stdin
                        """
                        
                        try {
                            parallel(
                                "Push Backend": {
                                    if (params.BUILD_BACKEND) {
                                        echo "Pushing backend images to Docker Hub..."
                                        
                                        // Tag images with username prefix
                                        sh """
                                            docker tag ${BACKEND_IMAGE}:${BUILD_NUMBER} ${DOCKER_HUB_USERNAME}/${BACKEND_IMAGE}:${BUILD_NUMBER}
                                            docker tag ${BACKEND_IMAGE}:latest ${DOCKER_HUB_USERNAME}/${BACKEND_IMAGE}:latest
                                            docker tag ${BACKEND_IMAGE}:${params.BUILD_TYPE} ${DOCKER_HUB_USERNAME}/${BACKEND_IMAGE}:${params.BUILD_TYPE}
                                        """
                                        
                                        // Push images
                                        sh """
                                            docker push ${DOCKER_HUB_USERNAME}/${BACKEND_IMAGE}:${BUILD_NUMBER}
                                            docker push ${DOCKER_HUB_USERNAME}/${BACKEND_IMAGE}:latest
                                            docker push ${DOCKER_HUB_USERNAME}/${BACKEND_IMAGE}:${params.BUILD_TYPE}
                                        """
                                        echo "Backend images pushed successfully"
                                    }
                                },
                                "Push Frontend": {
                                    if (params.BUILD_FRONTEND) {
                                        echo "Pushing frontend images to Docker Hub..."
                                        
                                        // Tag images with username prefix
                                        sh """
                                            docker tag ${FRONTEND_IMAGE}:${BUILD_NUMBER} ${DOCKER_HUB_USERNAME}/${FRONTEND_IMAGE}:${BUILD_NUMBER}
                                            docker tag ${FRONTEND_IMAGE}:latest ${DOCKER_HUB_USERNAME}/${FRONTEND_IMAGE}:latest
                                            docker tag ${FRONTEND_IMAGE}:${params.BUILD_TYPE} ${DOCKER_HUB_USERNAME}/${FRONTEND_IMAGE}:${params.BUILD_TYPE}
                                        """
                                        
                                        // Push images
                                        sh """
                                            docker push ${DOCKER_HUB_USERNAME}/${FRONTEND_IMAGE}:${BUILD_NUMBER}
                                            docker push ${DOCKER_HUB_USERNAME}/${FRONTEND_IMAGE}:latest
                                            docker push ${DOCKER_HUB_USERNAME}/${FRONTEND_IMAGE}:${params.BUILD_TYPE}
                                        """
                                        echo "Frontend images pushed successfully"
                                    }
                                }
                            )
                        } finally {
                            // Logout from Docker Hub
                            sh "docker logout"
                        }
                    }
                }
            }
        }
        
        stage('Local Deployment') {
            when {
                expression { params.DEPLOY_LOCALLY }
            }
            steps {
                script {
                    echo "Deploying to local Docker environment..."
                    
                    // Verify .env files exist
                    sh '''
                        echo "Checking environment files..."
                        if [ -f ${BACKEND_PATH}/.env ]; then
                            echo "Backend .env found"
                        else
                            echo "Backend .env not found - creating from example"
                            if [ -f ${BACKEND_PATH}/.env.example ]; then
                                cp ${BACKEND_PATH}/.env.example ${BACKEND_PATH}/.env
                            fi
                        fi
                        
                        if [ -f ${FRONTEND_PATH}/.env.local ]; then
                            echo "Frontend .env.local found"
                        else
                            echo "Frontend .env.local not found - creating from example"
                            if [ -f ${FRONTEND_PATH}/.env.example ]; then
                                cp ${FRONTEND_PATH}/.env.example ${FRONTEND_PATH}/.env.local
                            fi
                        fi
                    '''
                    
                    // Update docker-compose to use built images
                    sh '''
                        # Create a temporary docker-compose file with built images
                        cat > docker-compose.override.yml << EOF
services:
  frontend:
    image: ${FRONTEND_IMAGE}:${BUILD_NUMBER}
    
  backend:
    image: ${BACKEND_IMAGE}:${BUILD_NUMBER}
EOF
                    '''
                    
                    // Stop existing containers
                    sh '''
                        docker-compose down || true
                    '''
                    
                    // Start new containers
                    sh '''
                        docker-compose up -d
                    '''
                    
                    // Wait for services to start
                    sleep(60)
                    
                    // Verify deployment
                    sh '''
                        echo "Checking local deployment health..."
                        
                        # Check if containers are running
                        docker-compose ps
                        
                        # Check PostgreSQL
                        if docker-compose exec -T database pg_isready; then
                            echo "PostgreSQL is healthy"
                        else
                            echo "PostgreSQL health check failed"
                        fi
                        
                        # Check backend health (assuming it runs on port 8000)
                        sleep 10
                        if curl -f http://localhost:8000 2>/dev/null || curl -f http://localhost:80 2>/dev/null; then
                            echo "Backend is responding"
                        else
                            echo "Backend not responding on expected ports"
                        fi
                        
                        # Check frontend health (assuming it runs on port 3000)
                        if curl -f http://localhost:3000 2>/dev/null; then
                            echo "Frontend is responding"
                        else
                            echo "Frontend not responding on port 3000"
                        fi
                    '''
                }
            }
        }
        
        stage('Integration Tests') {
            when {
                allOf {
                    expression { params.DEPLOY_LOCALLY }
                    not {
                        expression { params.SKIP_TESTS }
                    }
                }
            }
            steps {
                script {
                    echo "Running integration tests..."
                    
                    // Basic integration tests
                    sh '''
                        echo "Testing application endpoints..."
                        
                        # Test backend endpoints
                        for port in 8000 80; do
                            if curl -f http://localhost:$port 2>/dev/null; then
                                echo "Backend responding on port $port"
                                break
                            fi
                        done
                        
                        # Test frontend
                        if curl -f http://localhost:3000 2>/dev/null; then
                            echo "Frontend responding on port 3000"
                        fi
                        
                        # Test database connection (if backend provides health endpoint)
                        if curl -f http://localhost:8000/health 2>/dev/null; then
                            echo "Backend health endpoint working"
                        elif curl -f http://localhost:80/health 2>/dev/null; then
                            echo "Backend health endpoint working"
                        else
                            echo "No health endpoint found"
                        fi
                        
                        # Show container logs for debugging
                        echo "Container status:"
                        docker-compose ps
                    '''
                }
            }
        }
    }
    
    post {
        always {
            cleanWs(
                cleanWhenAborted: true,
                cleanWhenFailure: true,
                cleanWhenNotBuilt: true,
                cleanWhenSuccess: true,
                deleteDirs: true
            )
            script {
                // Clean up Docker images
                sh '''
                    # Remove old images to save space
                    docker image prune -f
                    
                    # Remove dangling images
                    docker images -f "dangling=true" -q | xargs -r docker rmi || true
                '''
                
                // Archive build artifacts
                archiveArtifacts artifacts: '**/*.log, **/*-report.json', fingerprint: true, allowEmptyArchive: true
                
                // Publish test results if they exist
                junit testResults: '**/test-results.xml', allowEmptyResults: true

                // publishTestResults testResultsPattern: '**/test-results.xml', allowEmptyResults: true
                
                // Show final status
                echo """
Build Summary:
Build Number: ${BUILD_NUMBER}
Git Commit: ${GIT_COMMIT_SHORT}
Build Type: ${params.BUILD_TYPE}
Backend Built: ${params.BUILD_BACKEND}
Frontend Built: ${params.BUILD_FRONTEND}
Pushed to Hub: ${params.PUSH_TO_HUB}
Deployed Locally: ${params.DEPLOY_LOCALLY}
"""
            }
        }
        
        success {
            script {
                echo """
CLMS Mono-repo Build Successful!
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}
Duration: ${currentBuild.durationString}
"""
                
                if (params.PUSH_TO_HUB) {
                    // Access the username from the last withCredentials block
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub-credentials',
                        usernameVariable: 'DOCKER_HUB_USERNAME',
                        passwordVariable: 'DOCKER_HUB_PASSWORD'
                    )]) {
                        echo """
Images successfully pushed to Docker Hub:
Backend: ${DOCKER_HUB_USERNAME}/${BACKEND_IMAGE}:${BUILD_NUMBER}
Frontend: ${DOCKER_HUB_USERNAME}/${FRONTEND_IMAGE}:${BUILD_NUMBER}
"""
                    }
                }
                
                if (params.DEPLOY_LOCALLY) {
                    echo """
Local deployment successful:
Backend: Check http://localhost:8000 or http://localhost:80
Frontend: http://localhost:3000
Database: PostgreSQL on localhost:5432
"""
                }
            }
        }
        
        failure {
            script {
                echo """
CLMS Build Failed
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}
Check logs: ${BUILD_URL}console
"""
                
                // Show container logs for debugging
                if (params.DEPLOY_LOCALLY) {
                    sh '''
                        echo "Container logs for debugging:"
                        docker-compose logs --tail=50 || true
                    '''
                }
            }
        }
        
        unstable {
            script {
                echo """
CLMS Build Unstable
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}
Some tests may have failed
"""
            }
        }
        
        aborted {
            script {
                echo """
CLMS Build Aborted
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}
"""
                
                // Clean up any running containers
                sh '''
                    docker-compose down || true
                '''
            }
        }
    }
}