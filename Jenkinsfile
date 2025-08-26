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
                    sh 'docker compose version'
                    
                    // Detect changes in directories
                    echo "Detecting changes in mono-repo directories..."
                    
                    // Initialize variables
                    def backendChanged = false
                    def frontendChanged = false
                    
                    // Handle force build parameters first
                    if (params.FORCE_BUILD_ALL) {
                        backendChanged = true
                        frontendChanged = true
                        echo "Force build all enabled - will build both backend and frontend"
                    env.ACTUALLY_DEPLOYED_LOCALLY = deployLocally.toString()
                    } else if (params.FORCE_BACKEND_ONLY) {
                        backendChanged = true
                        frontendChanged = false
                        echo "Force backend only enabled - will build backend only"
                    } else if (params.FORCE_FRONTEND_ONLY) {
                        backendChanged = false
                        frontendChanged = true
                        echo "Force frontend only enabled - will build frontend only"
                    } else {
                        echo "Auto-detecting changes..."
                        
                        // Check if this is the first build or if we can detect changes
                        try {
                            // Get the previous successful build commit - using correct Jenkins API
                            def previousCommit = ''
                            def previousBuild = currentBuild.getPreviousBuild()
                            
                            // Look for the last successful build
                            while (previousBuild != null) {
                                if (previousBuild.getResult() == null || previousBuild.getResult().toString() == 'SUCCESS') {
                                    try {
                                        def previousEnv = previousBuild.getBuildVariables()
                                        if (previousEnv.containsKey('GIT_COMMIT')) {
                                            previousCommit = previousEnv['GIT_COMMIT']
                                            break
                                        }
                                    } catch (Exception envEx) {
                                        // Try alternative method
                                        def previousActions = previousBuild.getAllActions()
                                        for (action in previousActions) {
                                            if (action.hasProperty('lastBuiltRevision') && action.lastBuiltRevision != null) {
                                                previousCommit = action.lastBuiltRevision.getSha1String()
                                                break
                                            }
                                        }
                                        if (previousCommit) break
                                    }
                                }
                                previousBuild = previousBuild.getPreviousBuild()
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
                    }
                    
                    // Store decision variables globally for use in other stages
                    env.BACKEND_CHANGED = backendChanged.toString()
                    env.FRONTEND_CHANGED = frontendChanged.toString()
                    env.BUILD_BACKEND = backendChanged.toString()
                    env.BUILD_FRONTEND = frontendChanged.toString()
                    
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
                    echo """
Starting CLMS Mono-repo Build Pipeline
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}

Change Detection Results:
Backend Changed: ${env.BACKEND_CHANGED}
Frontend Changed: ${env.FRONTEND_CHANGED}

Build Decision:
Backend Will Build: ${env.BUILD_BACKEND}
Frontend Will Build: ${env.BUILD_FRONTEND}

Additional Settings:
Push to Hub: ${params.PUSH_TO_HUB}
Deploy Locally: ${params.DEPLOY_LOCALLY}
"""

                    if (env.BUILD_BACKEND == 'false' && env.BUILD_FRONTEND == 'false') {
                        echo "No components to build - pipeline will skip build stages"
                    }
                }
            }
        }
        
        stage('Code Quality & Security') {
            steps {
                script {
                    // Use script-based conditionals instead of when clauses
                    def parallelStages = [:]
                    
                    if (env.BUILD_BACKEND == 'true') {
                        parallelStages['Backend Security Scan'] = {
                            dir("${BACKEND_PATH}") {
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
                    
                    if (env.BUILD_FRONTEND == 'true') {
                        parallelStages['Frontend Security Scan'] = {
                            dir("${FRONTEND_PATH}") {
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
                    
                    if (env.BUILD_BACKEND == 'true' || env.BUILD_FRONTEND == 'true') {
                        parallelStages['Secret Scanning'] = {
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
                    
                    if (parallelStages.size() > 0) {
                        parallel parallelStages
                    } else {
                        echo "Skipping security scans - no components to build"
                    }
                }
            }
        }
        
        stage('Build & Test') {
            steps {
                script {
                    if (env.BUILD_BACKEND == 'false' && env.BUILD_FRONTEND == 'false') {
                        echo "Skipping build stage - no components to build"
                        return
                    }
                    
                    def parallelStages = [:]
                    
                    if (env.BUILD_BACKEND == 'true') {
                        parallelStages['Backend Build & Test'] = {
                            // Backend Build
                            dir("${BACKEND_PATH}") {
                                echo "Building backend Docker image..."
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
                            
                            // Backend Tests
                            if (!params.SKIP_TESTS) {
                                dir("${BACKEND_PATH}") {
                                    echo "Running backend tests..."
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
                                    
                                    // if (fileExists('test-results.xml')) {
                                    //     junit testResults: 'test-results.xml', allowEmptyResults: true
                                    // }
                                    if (fileExists('test-results.xml')) {
                                        echo "Publishing backend test results..."
                                        junit testResults: 'test-results.xml', allowEmptyResults: true
                                        archiveArtifacts artifacts: 'test-results.xml', fingerprint: true, allowEmptyArchive: true
                                    } else {
                                        echo "No backend test results file found"
                                    }

                                    sh 'find . -name "*.log" -type f -exec echo "Found log: {}" \\;'
                                    archiveArtifacts artifacts: '**/*.log', fingerprint: true, allowEmptyArchive: true
                                }
                            }
                            
                            // Backend Quality
                            dir("${BACKEND_PATH}") {
                                echo "Running backend quality checks..."
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
                    
                    if (env.BUILD_FRONTEND == 'true') {
                        parallelStages['Frontend Build & Test'] = {
                            // Frontend Build
                            dir("${FRONTEND_PATH}") {
                                echo "Building frontend Docker image..."
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
                            
                            // Frontend Tests
                            if (!params.SKIP_TESTS) {
                                dir("${FRONTEND_PATH}") {
                                    echo "Running frontend tests..."
                                    sh '''
                                        if [ -f package.json ]; then
                                            echo "Available npm scripts:"
                                            cat package.json | jq '.scripts' || cat package.json | grep -A 10 '"scripts"'
                                        else
                                            echo "package.json not found"
                                        fi
                                    '''
                                    
                                    sh '''
                                        docker run --rm \
                                            -v $(pwd):/app \
                                            -w /app \
                                            ${FRONTEND_IMAGE}:${BUILD_NUMBER} \
                                            sh -c "npm test || echo 'No test script found'" || true
                                    '''
                                    
                                    sh '''
                                        docker run --rm \
                                            -v $(pwd):/app \
                                            -w /app \
                                            ${FRONTEND_IMAGE}:${BUILD_NUMBER} \
                                            sh -c "npm run lint || echo 'No lint script found'" || true
                                    '''
                                }
                            }
                            
                            // Frontend Quality
                            dir("${FRONTEND_PATH}") {
                                echo "Running frontend quality checks..."
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
                    
                    parallel parallelStages
                }
            }
        }
        
        stage('Security Scanning') {
            steps {
                script {
                    if (env.BUILD_BACKEND == 'false' && env.BUILD_FRONTEND == 'false') {
                        echo "Skipping security scanning - no components built"
                        return
                    }
                    
                    def parallelStages = [:]
                    
                    if (env.BUILD_BACKEND == 'true') {
                        parallelStages['Backend Image Scan'] = {
                            echo "Running backend security scan..."
                            // sh """
                            //     docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            //         aquasec/trivy:latest image \
                            //         --exit-code 0 \
                            //         --severity HIGH,CRITICAL \
                            //         --format json \
                            //         --output backend-security-report.json \
                            //         ${BACKEND_IMAGE}:${BUILD_NUMBER} || true
                            // """
                            
                            // if (fileExists('backend-security-report.json')) {
                            //     archiveArtifacts artifacts: 'backend-security-report.json', fingerprint: true
                            // }
                            sh """
                                docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                                    aquasec/trivy:latest image \
                                    --exit-code 0 \
                                    --severity HIGH,CRITICAL \
                                    --format table \
                                    --output backend-security-report.txt \
                                    ${BACKEND_IMAGE}:${BUILD_NUMBER} || true
                                    
                                docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                                    aquasec/trivy:latest image \
                                    --exit-code 0 \
                                    --severity HIGH,CRITICAL \
                                    --format json \
                                    --output backend-security-report.json \
                                    ${BACKEND_IMAGE}:${BUILD_NUMBER} || true
                            """

                            script {
                                if (fileExists('backend-security-report.json')) {
                                    archiveArtifacts artifacts: 'backend-security-report.json', fingerprint: true
                                    echo "Backend security report archived"
                                }
                                if (fileExists('backend-security-report.txt')) {
                                    archiveArtifacts artifacts: 'backend-security-report.txt', fingerprint: true
                                    echo "Backend security report (readable) archived"
                                }
                            }
                        }
                    }
                    
                    if (env.BUILD_FRONTEND == 'true') {
                        parallelStages['Frontend Image Scan'] = {
                            echo "Running frontend security scan..."
                            // sh """
                            //     docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            //         aquasec/trivy:latest image \
                            //         --exit-code 0 \
                            //         --severity HIGH,CRITICAL \
                            //         --format json \
                            //         --output frontend-security-report.json \
                            //         ${FRONTEND_IMAGE}:${BUILD_NUMBER} || true
                            // """
                            
                            // if (fileExists('frontend-security-report.json')) {
                            //     archiveArtifacts artifacts: 'frontend-security-report.json', fingerprint: true
                            // }
                            sh """
                                docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                                    aquasec/trivy:latest image \
                                    --exit-code 0 \
                                    --severity HIGH,CRITICAL \
                                    --format table \
                                    --output frontend-security-report.txt \
                                    ${FRONTEND_IMAGE}:${BUILD_NUMBER} || true
                                    
                                docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                                    aquasec/trivy:latest image \
                                    --exit-code 0 \
                                    --severity HIGH,CRITICAL \
                                    --format json \
                                    --output frontend-security-report.json \
                                    ${FRONTEND_IMAGE}:${BUILD_NUMBER} || true
                            """

                            script {
                                if (fileExists('frontend-security-report.json')) {
                                    archiveArtifacts artifacts: 'frontend-security-report.json', fingerprint: true
                                    echo "Frontend security report archived"
                                }
                                if (fileExists('frontend-security-report.txt')) {
                                    archiveArtifacts artifacts: 'frontend-security-report.txt', fingerprint: true
                                    echo "frontend security report (readable) archived"
                                }
                            }
                        }
                    }
                    
                    parallel parallelStages
                }
            }
        }
        
        stage('Push to Docker Hub') {
            steps {
                script {
                    if (!params.PUSH_TO_HUB) {
                        echo "Skipping Docker Hub push - disabled by parameter"
                        return
                    }
                    
                    if (env.BUILD_BACKEND == 'false' && env.BUILD_FRONTEND == 'false') {
                        echo "Skipping Docker Hub push - no components built"
                        return
                    }
                    
                    echo "Pushing images to Docker Hub..."
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub-credentials',
                        usernameVariable: 'DOCKER_HUB_USERNAME',
                        passwordVariable: 'DOCKER_HUB_PASSWORD'
                    )]) {
                        sh '''
                            echo "$DOCKER_HUB_PASSWORD" | docker login -u "$DOCKER_HUB_USERNAME" --password-stdin
                        '''
                        
                        try {
                            def parallelPushes = [:]
                            
                            if (env.BUILD_BACKEND == 'true') {
                                parallelPushes['Push Backend'] = {
                                    echo "Pushing backend images to Docker Hub..."
                                    
                                    sh '''
                                        docker tag ${BACKEND_IMAGE}:${BUILD_NUMBER} $DOCKER_HUB_USERNAME/${BACKEND_IMAGE}:${BUILD_NUMBER}
                                        docker tag ${BACKEND_IMAGE}:latest $DOCKER_HUB_USERNAME/${BACKEND_IMAGE}:latest
                                        docker tag ${BACKEND_IMAGE}:${BUILD_TYPE} $DOCKER_HUB_USERNAME/${BACKEND_IMAGE}:${BUILD_TYPE}
                                    '''

                                    sh '''
                                        docker push $DOCKER_HUB_USERNAME/${BACKEND_IMAGE}:${BUILD_NUMBER}
                                        docker push $DOCKER_HUB_USERNAME/${BACKEND_IMAGE}:latest
                                        docker push $DOCKER_HUB_USERNAME/${BACKEND_IMAGE}:${BUILD_TYPE}
                                    '''
                                    echo "Backend images pushed successfully"
                                }
                            }
                            
                            if (env.BUILD_FRONTEND == 'true') {
                                parallelPushes['Push Frontend'] = {
                                    echo "Pushing frontend images to Docker Hub..."
                                    
                                    sh '''
                                        docker tag ${FRONTEND_IMAGE}:${BUILD_NUMBER} $DOCKER_HUB_USERNAME/${FRONTEND_IMAGE}:${BUILD_NUMBER}
                                        docker tag ${FRONTEND_IMAGE}:latest $DOCKER_HUB_USERNAME/${FRONTEND_IMAGE}:latest
                                        docker tag ${FRONTEND_IMAGE}:${BUILD_TYPE} $DOCKER_HUB_USERNAME/${FRONTEND_IMAGE}:${BUILD_TYPE}
                                    '''

                                    sh '''
                                        docker push $DOCKER_HUB_USERNAME/${FRONTEND_IMAGE}:${BUILD_NUMBER}
                                        docker push $DOCKER_HUB_USERNAME/${FRONTEND_IMAGE}:latest
                                        docker push $DOCKER_HUB_USERNAME/${FRONTEND_IMAGE}:${BUILD_TYPE}
                                    '''
                                    echo "Frontend images pushed successfully"
                                }
                            }
                            
                            parallel parallelPushes
                        } finally {
                            sh "docker logout"
                        }
                    }
                }
            }
        }
        
        stage('Local Deployment') {
            steps {
                script {
                    
                    // Initialize deployment status
                    env.ACTUALLY_DEPLOYED_LOCALLY = 'false'
   
                    if (env.BUILD_BACKEND == 'false' && env.BUILD_FRONTEND == 'false') {
                        echo "Skipping local deployment - no components built"
                        return
                    }
                    
                    // Prompt user whether to proceed with local deployment
                    def deployLocally = false
                    
                    if (params.DEPLOY_LOCALLY) {
                        // If parameter is already true, just deploy
                        deployLocally = false
                        echo "Local deployment enabled by parameter - proceeding automatically"
                    } else {
                        // Ask user for confirmation
                        try {
                            timeout(time: 5, unit: 'MINUTES') {
                                input message: 'Do you want to deploy to local Docker environment?', 
                                      ok: 'Deploy Locally',
                                      submitterParameter: 'SUBMITTER'
                                deployLocally = true
                                echo "User confirmed local deployment"
                            }
                        } catch (Exception e) {
                            echo "Local deployment declined or timed out: ${e.getMessage()}"
                            deployLocally = false
                        }
                    }
                    
                    if (!deployLocally) {
                        echo "Skipping local deployment - user declined or disabled"
                        return
                    }
                    
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
                        
                        # Check if main .env file exists for database variables
                        if [ ! -f .env ]; then
                            echo "Creating main .env file for database"
                            cat > .env << EOF
POSTGRES_USER=postgresuser
POSTGRES_PASSWORD=postgrespass
POSTGRES_DB=clms
REDIS_PASSWORD=redis123
EOF
                        fi
                    '''
                    // Stop existing containers first
                    sh '''
                        echo "Stopping existing containers..."
                        docker compose down --remove-orphans || true
                    '''
                    
                    // Tag the built images to match what docker-compose expects, or modify the compose approach
                    if (env.BUILD_BACKEND == 'true' || env.BUILD_FRONTEND == 'true') {
                        sh '''
                            # Create a simple override that uses our built images instead of building
                            cat > docker-compose.override.yml << 'EOF'
services:
EOF
                        '''
                        
                        if (env.BUILD_BACKEND == 'true') {
                            sh """
                                cat >> docker-compose.override.yml << 'EOF'
  backend:
    image: ${BACKEND_IMAGE}:${BUILD_NUMBER}
EOF
                            """
                        }
                        
                        if (env.BUILD_FRONTEND == 'true') {
                            sh """
                                cat >> docker-compose.override.yml << 'EOF'
  frontend:
    image: ${FRONTEND_IMAGE}:${BUILD_NUMBER}
    volumes: ~
    container_name: clms_frontend
    network_mode: "host"
    env_file:
    - ./front-end/.env.local
    restart: unless-stopped
    depends_on:
    - backend
EOF
                            """
                        }
                        
                        echo "Generated docker-compose.override.yml:"
                        sh 'cat docker-compose.override.yml'
                    }
                    
                    // Start services using your existing compose file + override
                    sh '''
                        echo "Starting services with docker-compose..."
                        docker compose up -d
                        
                        echo "Waiting for services to start..."
                        sleep 30
                        
                        echo "Container status:"
                        docker compose ps
                    '''
                    
                    // Wait for health checks
                    sh '''
                        echo "Waiting for health checks..."
                        
                        # Wait up to 2 minutes for services to be healthy
                        for i in $(seq 1 24); do
                            echo "Health check attempt $i/24"
                            
                            # Check database health
                            if docker compose exec -T database pg_isready -U postgresuser -d clms; then
                                echo "Database is healthy"
                                DB_HEALTHY=true
                            else
                                echo "Database not ready yet"
                                DB_HEALTHY=false
                            fi
                            
                            # Check Redis
                            if docker compose exec -T redis redis-cli -a redis123 ping | grep PONG > /dev/null; then
                                echo "Redis is healthy"
                                REDIS_HEALTHY=true
                            else
                                echo "Redis not ready yet"
                                REDIS_HEALTHY=false
                            fi
                            
                            # Check if containers are running
                            RUNNING=$(docker compose ps --format "table {{.Service}}\\t{{.Status}}" | grep -c "running" || true)
                            TOTAL=$(docker compose ps --format "table {{.Service}}" | tail -n +2 | wc -l || true)
                            
                            echo "Services running: $RUNNING/$TOTAL"
                            
                            if [ "$RUNNING" = "$TOTAL" ] && [ "$DB_HEALTHY" = "true" ] && [ "$REDIS_HEALTHY" = "true" ]; then
                                echo "All infrastructure services are healthy"
                                break
                            fi
                            
                            if [ "$i" = "24" ]; then
                                echo "Timeout waiting for services to be healthy"
                                echo "=== Container Status ==="
                                docker compose ps
                                echo "=== Recent Logs ==="
                                docker compose logs --tail=20
                            fi
                            
                            sleep 5
                        done
                    '''
                    
                    // Verify deployment endpoints
                    sh '''
                        echo "Testing service endpoints..."
                        
                        # Test backend (host network, so should be on localhost:8000)
                        if curl -f http://localhost:8000 >/dev/null 2>&1; then
                            echo "Backend responding on localhost:8000"
                        else
                            echo "Backend not responding on localhost:8000"
                            echo "Checking backend logs:"
                            docker compose logs backend --tail=10
                        fi
                        
                        # Test frontend (host network, so should be on localhost:3000)  
                        if curl -f http://localhost:3000 >/dev/null 2>&1; then
                            echo "Frontend responding on localhost:3000"
                        else
                            echo "Frontend not responding on localhost:3000"
                            echo "Checking frontend logs:"
                            docker compose logs frontend --tail=10
                        fi
                        
                        # Test database connection
                        if docker compose exec -T database psql -U postgresuser -d clms -c "SELECT 1;" >/dev/null 2>&1; then
                            echo "Database connection successful"
                        else
                            echo "Database connection failed"
                        fi
                        
                        # Test Redis
                        if docker compose exec -T redis redis-cli -a redis123 ping >/dev/null 2>&1; then
                            echo "Redis connection successful"
                        else
                            echo "Redis connection failed"
                        fi
                    '''
                }
            }
        }
        
        stage('Integration Tests') {
            steps {
                script {
                    if (env.ACTUALLY_DEPLOYED_LOCALLY != 'true') {
                        echo "Skipping integration tests - local deployment was not performed"
                        return
                    }
                    
                    if (params.SKIP_TESTS) {
          z              echo "Skipping integration tests - disabled by parameter"
                        return
                    }
                    
                    if (env.BUILD_BACKEND == 'false' && env.BUILD_FRONTEND == 'false') {
                        echo "Skipping integration tests - no components built"
                        return
                    }
                    
                    echo "Running integration tests..."
                    
                    sh '''
                        echo "Testing application endpoints..."
                        
                        # Test backend endpoints
                        if curl -f http://localhost:8000 2>/dev/null; then
                            echo "Backend responding on port 8000"
                        fi
                        
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
                
                // // Archive build artifacts
                // archiveArtifacts artifacts: '**/*.log, **/*-report.json', fingerprint: true, allowEmptyArchive: true
                
                // // Publish test results if they exist
                // junit testResults: '**/test-results.xml', allowEmptyResults: 

                echo "Collecting build artifacts..."
                sh '''
                    echo "=== Searching for artifacts ==="
                    find . -name "*-report.json" -o -name "*-report.txt" -o -name "test-results.xml" -o -name "*.log" | head -20
                '''

                archiveArtifacts artifacts: '**/*-report.json, **/*-report.txt, **/test-results.xml, **/*.log', 
                                fingerprint: true, 
                                allowEmptyArchive: true

                script {
                    try {
                        junit testResults: '**/test-results.xml', allowEmptyResults: true
                        echo "Test results published successfully"
                    } catch (Exception e) {
                        echo "No test results to publish: ${e.getMessage()}"
                    }
                }
                
                // Show final status
                echo """
Build Summary:
Build Number: ${BUILD_NUMBER}
Git Commit: ${GIT_COMMIT_SHORT}
Build Type: ${params.BUILD_TYPE}
Backend Changed: ${env.BACKEND_CHANGED}
Frontend Changed: ${env.FRONTEND_CHANGED}
Backend Built: ${env.BUILD_BACKEND}
Frontend Built: ${env.BUILD_FRONTEND}
Pushed to Hub: ${params.PUSH_TO_HUB}
Deployed Locally: ${params.DEPLOY_LOCALLY}
"""
            }
        }
        
        success {
            script {
                def backendBuilt = env.BUILD_BACKEND == 'true'
                def frontendBuilt = env.BUILD_FRONTEND == 'true'
                
                echo """
CLMS Mono-repo Build Successful!
Build Number: ${BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Build Type: ${params.BUILD_TYPE}
Duration: ${currentBuild.durationString}
Components Built: ${backendBuilt ? 'Backend' : ''}${backendBuilt && frontendBuilt ? ' + ' : ''}${frontendBuilt ? 'Frontend' : ''}${!backendBuilt && !frontendBuilt ? 'None (no changes detected)' : ''}
"""
                
                if (params.PUSH_TO_HUB && (backendBuilt || frontendBuilt)) {
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
Backend Built: ${env.BUILD_BACKEND}
Frontend Built: ${env.BUILD_FRONTEND}
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
Backend Built: ${env.BUILD_BACKEND}
Frontend Built: ${env.BUILD_FRONTEND}
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