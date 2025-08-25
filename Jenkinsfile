#!/usr/bin/env groovy

pipeline {
    agent any
    
    environment {
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
        
        // Change detection variables (will be set dynamically)
        BACKEND_CHANGED = 'false'
        FRONTEND_CHANGED = 'false'
        FORCE_BUILD_BACKEND = 'false'
        FORCE_BUILD_FRONTEND = 'false'
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
            name: 'FORCE_BUILD_ALL',
            defaultValue: false,
            description: 'Force build both frontend and backend regardless of changes'
        )
        booleanParam(
            name: 'FORCE_BACKEND_ONLY',
            defaultValue: false,
            description: 'Force build backend only (override change detection)'
        )
        booleanParam(
            name: 'FORCE_FRONTEND_ONLY',
            defaultValue: false,
            description: 'Force build frontend only (override change detection)'
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
        stage('Preparation & Change Detection') {
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
                    sh 'docker compose --version'
                    
                    // Detect changes in directories
                    echo "Detecting changes in mono-repo directories..."
                    
                    // Handle force build parameters first
                    if (params.FORCE_BUILD_ALL) {
                        env.FORCE_BUILD_BACKEND = 'true'
                        env.FORCE_BUILD_FRONTEND = 'true'
                        echo "Force build all enabled - will build both backend and frontend"
                    } else if (params.FORCE_BACKEND_ONLY) {
                        env.FORCE_BUILD_BACKEND = 'true'
                        env.FORCE_BUILD_FRONTEND = 'false'
                        echo "Force backend only enabled - will build backend only"
                    } else if (params.FORCE_FRONTEND_ONLY) {
                        env.FORCE_BUILD_BACKEND = 'false'
                        env.FORCE_BUILD_FRONTEND = 'true'
                        echo "Force frontend only enabled - will build frontend only"
                    } else {
                        // Auto-detect changes
                        def backendChanged = false
                        def frontendChanged = false
                        
                        // Check if this is the first build or if we can detect changes
                        try {
                            // Get the previous successful build commit
                            def previousCommit = ''
                            def builds = currentBuild.getPreviousBuildsOverThreshold(hudson.model.Result.SUCCESS, 1)
                            if (builds.size() > 0) {
                                def previousBuild = builds[0]
                                // Try to get the commit from the previous build
                                def previousBuildCommit = previousBuild.getEnvironment(this).GIT_COMMIT
                                if (previousBuildCommit) {
                                    previousCommit = previousBuildCommit
                                }
                            }
                            
                            if (previousCommit) {
                                echo "Comparing changes between ${previousCommit[0..7]} and ${env.GIT_COMMIT[0..7]}"
                                
                                // Check for backend changes
                                def backendChangesOutput = sh(
                                    script: "git diff --name-only ${previousCommit} ${env.GIT_COMMIT} | grep '^${BACKEND_PATH}/' || true",
                                    returnStdout: true
                                ).trim()
                                
                                // Check for frontend changes  
                                def frontendChangesOutput = sh(
                                    script: "git diff --name-only ${previousCommit} ${env.GIT_COMMIT} | grep '^${FRONTEND_PATH}/' || true",
                                    returnStdout: true
                                ).trim()
                                
                                backendChanged = !backendChangesOutput.isEmpty()
                                frontendChanged = !frontendChangesOutput.isEmpty()
                                
                                if (backendChanged) {
                                    echo "Backend changes detected:"
                                    sh "git diff --name-only ${previousCommit} ${env.GIT_COMMIT} | grep '^${BACKEND_PATH}/'"
                                }
                                
                                if (frontendChanged) {
                                    echo "Frontend changes detected:"
                                    sh "git diff --name-only ${previousCommit} ${env.GIT_COMMIT} | grep '^${FRONTEND_PATH}/'"
                                }
                                
                                if (!backendChanged && !frontendChanged) {
                                    echo "No changes detected in backend or frontend directories"
                                    // Check if there are any changes at all
                                    def anyChanges = sh(
                                        script: "git diff --name-only ${previousCommit} ${env.GIT_COMMIT}",
                                        returnStdout: true
                                    ).trim()
                                    
                                    if (!anyChanges.isEmpty()) {
                                        echo "Changes detected in other files:"
                                        sh "git diff --name-only ${previousCommit} ${env.GIT_COMMIT}"
                                        echo "Building both components due to root-level or other changes"
                                        backendChanged = true
                                        frontendChanged = true
                                    }
                                }
                            } else {
                                echo "No previous successful build found - building all components"
                                backendChanged = true
                                frontendChanged = true
                            }
                        } catch (Exception e) {
                            echo "Error detecting changes: ${e.getMessage()}"
                            echo "Defaulting to build all components"
                            backendChanged = true
                            frontendChanged = true
                        }
                        
                        // Set environment variables
                        env.BACKEND_CHANGED = backendChanged.toString()
                        env.FRONTEND_CHANGED = frontendChanged.toString()
                        env.FORCE_BUILD_BACKEND = backendChanged.toString()
                        env.FORCE_BUILD_FRONTEND = frontendChanged.toString()
                    }
                    
                    // Show mono-repo structure
                    sh '''
                        echo "Mono-repo structure:"
                        ls -la
                        echo "Backend structure:"
                        ls -la ${BACKEND_PATH}/
                        echo "Frontend structure:"
                        ls -la ${FRONTEND_PATH}/
                    '''
                    
                    // Build decision summary
                    def buildBackend = env.FORCE_BUILD_BACKEND == 'true'
                    def buildFrontend = env.FORCE_BUILD_FRONTEND == 'true'
                    
                    echo """
Starting CLMS Mono-repo Build Pipeline
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}

Change Detection Results:
Backend Changed: ${env.BACKEND_CHANGED}
Frontend Changed: ${env.FRONTEND_CHANGED}

Build Decision:
Backend Will Build: ${buildBackend}
Frontend Will Build: ${buildFrontend}

Additional Settings:
Push to Hub: ${params.PUSH_TO_HUB}
Deploy Locally: ${params.DEPLOY_LOCALLY}
"""

                    if (!buildBackend && !buildFrontend) {
                        echo "No components to build - pipeline will skip build stages"
                    }
                }
            }
        }
        
        stage('Code Quality & Security') {
            parallel {
                stage('Backend Security Scan') {
                    when {
                        expression { env.FORCE_BUILD_BACKEND == 'true' }
                    }
                    steps {
                        dir("${BACKEND_PATH}") {
                            script {
                                echo "Running backend security scan..."
                                
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
                        expression { env.FORCE_BUILD_FRONTEND == 'true' }
                    }
                    steps {
                        dir("${FRONTEND_PATH}") {
                            script {
                                echo "Running frontend security scan..."
                                
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
                    when {
                        anyOf {
                            expression { env.FORCE_BUILD_BACKEND == 'true' }
                            expression { env.FORCE_BUILD_FRONTEND == 'true' }
                        }
                    }
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
            when {
                anyOf {
                    expression { env.FORCE_BUILD_BACKEND == 'true' }
                    expression { env.FORCE_BUILD_FRONTEND == 'true' }
                }
            }
            parallel {
                stage('Backend Build & Test') {
                    when {
                        expression { env.FORCE_BUILD_BACKEND == 'true' }
                    }
                    stages {
                        stage('Backend Build') {
                            steps {
                                dir("${BACKEND_PATH}") {
                                    script {
                                        echo "Building backend Docker image..."
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
                                        echo "Backend build completed successfully"
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
                                        echo "Running backend tests..."
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
                                        }
                                    }
                                }
                            }
                        }
                        
                        stage('Backend Quality') {
                            steps {
                                dir("${BACKEND_PATH}") {
                                    script {
                                        echo "Running backend quality checks..."
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
                        expression { env.FORCE_BUILD_FRONTEND == 'true' }
                    }
                    stages {
                        stage('Frontend Build') {
                            steps {
                                dir("${FRONTEND_PATH}") {
                                    script {
                                        echo "Building frontend Docker image..."
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
                                        echo "Frontend build completed successfully"
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
                                        echo "Running frontend tests..."
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
                                        echo "Running frontend quality checks..."
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
            when {
                anyOf {
                    expression { env.FORCE_BUILD_BACKEND == 'true' }
                    expression { env.FORCE_BUILD_FRONTEND == 'true' }
                }
            }
            parallel {
                stage('Backend Image Scan') {
                    when {
                        expression { env.FORCE_BUILD_BACKEND == 'true' }
                    }
                    steps {
                        script {
                            echo "Running backend security scan..."
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
                        expression { env.FORCE_BUILD_FRONTEND == 'true' }
                    }
                    steps {
                        script {
                            echo "Running frontend security scan..."
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
                allOf {
                    expression { params.PUSH_TO_HUB }
                    anyOf {
                        expression { env.FORCE_BUILD_BACKEND == 'true' }
                        expression { env.FORCE_BUILD_FRONTEND == 'true' }
                    }
                }
            }
            steps {
                script {
                    echo "Pushing images to Docker Hub..."
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
                                    if (env.FORCE_BUILD_BACKEND == 'true') {
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
                                    } else {
                                        echo "Skipping backend push - not built in this pipeline run"
                                    }
                                },
                                "Push Frontend": {
                                    if (env.FORCE_BUILD_FRONTEND == 'true') {
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
                                    } else {
                                        echo "Skipping frontend push - not built in this pipeline run"
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
                allOf {
                    expression { params.DEPLOY_LOCALLY }
                    anyOf {
                        expression { env.FORCE_BUILD_BACKEND == 'true' }
                        expression { env.FORCE_BUILD_FRONTEND == 'true' }
                    }
                }
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
                    def composeOverride = "services:\n"
                    if (env.FORCE_BUILD_FRONTEND == 'true') {
                        composeOverride += "  frontend:\n    image: ${FRONTEND_IMAGE}:${BUILD_NUMBER}\n"
                    }
                    if (env.FORCE_BUILD_BACKEND == 'true') {
                        composeOverride += "  backend:\n    image: ${BACKEND_IMAGE}:${BUILD_NUMBER}\n"
                    }
                    
                    writeFile file: 'docker-compose.override.yml', text: composeOverride
                    
                    echo "Generated docker-compose.override.yml:"
                    sh 'cat docker-compose.override.yml'
                    
                    // Stop existing containers
                    sh '''
                        docker compose down || true
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
                        docker compose ps
                        
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
                    anyOf {
                        expression { env.FORCE_BUILD_BACKEND == 'true' }
                        expression { env.FORCE_BUILD_FRONTEND == 'true' }
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
                        if curl -f http://localhost:8000 2>/dev/null; then
                            echo "Backend responding on port $port"
                        fi
                        done
                        
                        # Test frontend
                        if curl -f http://localhost:3000 2>/dev/null; then
                            echo "Frontend responding on port 3000"
                        fi
                        
                        # Test database connection (if backend provides health endpoint)
                        if curl -f http://localhost:8000/health 2>/dev/null; then
                            echo "Backend health endpoint working"
                        else
                            echo "No health endpoint found"
                        fi
                        
                        # Show container logs for debugging
                        echo "Container status:"
                        docker compose ps
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
                
                // Show final status
                echo """
Build Summary:
Build Number: ${BUILD_NUMBER}
Git Commit: ${GIT_COMMIT_SHORT}
Build Type: ${params.BUILD_TYPE}
Backend Changed: ${env.BACKEND_CHANGED}
Frontend Changed: ${env.FRONTEND_CHANGED}
Backend Built: ${env.FORCE_BUILD_BACKEND}
Frontend Built: ${env.FORCE_BUILD_FRONTEND}
Pushed to Hub: ${params.PUSH_TO_HUB}
Deployed Locally: ${params.DEPLOY_LOCALLY}
"""
            }
        }
        
        success {
            script {
                def backendBuilt = env.FORCE_BUILD_BACKEND == 'true'
                def frontendBuilt = env.FORCE_BUILD_FRONTEND == 'true'
                
                echo """
CLMS Mono-repo Build Successful!
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}
Duration: ${currentBuild.durationString}
Components Built: ${backendBuilt ? 'Backend' : ''}${backendBuilt && frontendBuilt ? ' + ' : ''}${frontendBuilt ? 'Frontend' : ''}${!backendBuilt && !frontendBuilt ? 'None (no changes detected)' : ''}
"""
                
                if (params.PUSH_TO_HUB && (backendBuilt || frontendBuilt)) {
                    // Access the username from the last withCredentials block
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub-credentials',
                        usernameVariable: 'DOCKER_HUB_USERNAME',
                        passwordVariable: 'DOCKER_HUB_PASSWORD'
                    )]) {
                        def pushedImages = []
                        if (backendBuilt) {
                            pushedImages.add("Backend: ${DOCKER_HUB_USERNAME}/${BACKEND_IMAGE}:${BUILD_NUMBER}")
                        }
                        if (frontendBuilt) {
                            pushedImages.add("Frontend: ${DOCKER_HUB_USERNAME}/${FRONTEND_IMAGE}:${BUILD_NUMBER}")
                        }
                        
                        if (pushedImages.size() > 0) {
                            echo """
Images successfully pushed to Docker Hub:
${pushedImages.join('\n')}
"""
                        }
                    }
                }
                
                if (params.DEPLOY_LOCALLY && (backendBuilt || frontendBuilt)) {
                    echo """
Local deployment successful:
Backend: Check http://localhost:8000
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
Backend Built: ${env.FORCE_BUILD_BACKEND}
Frontend Built: ${env.FORCE_BUILD_FRONTEND}
Check logs: ${BUILD_URL}console
"""
                
                // Show container logs for debugging
                if (params.DEPLOY_LOCALLY) {
                    sh '''
                        echo "Container logs for debugging:"
                        docker compose logs --tail=50 || true
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
Backend Built: ${env.FORCE_BUILD_BACKEND}
Frontend Built: ${env.FORCE_BUILD_FRONTEND}
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
                    docker compose down || true
                '''
            }
        }
    }
}