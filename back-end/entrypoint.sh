#!/bin/sh
set -e

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to wait for database
wait_for_db() {
    local host="${DB_HOST:-postgres}"
    local port="${DB_PORT:-5432}"
    local max_attempts="${DB_WAIT_TIMEOUT:-30}"
    local attempt=1
    
    log_info "Waiting for database at $host:$port (max $max_attempts seconds)..."
    
    while [ $attempt -le $max_attempts ]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            log_info "Database is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done
    
    log_error "Database connection timeout after $max_attempts seconds"
    return 1
}

# Function to setup storage directories
setup_storage() {
    log_info "Setting up storage directories..."
    
    local dirs="
        storage/app/public
        storage/framework/cache/data
        storage/framework/sessions
        storage/framework/views
        storage/logs
        bootstrap/cache
    "
    
    for dir in $dirs; do
        mkdir -p "$dir" 2>/dev/null || true
    done
    
    # Try to set permissions, but don't fail if we can't
    if [ -w storage ]; then
        chmod -R 755 storage bootstrap/cache 2>/dev/null || true
    else
        log_warn "Running as non-root, skipping permission changes"
    fi
}

# Function to handle .env file and APP_KEY
setup_env_file() {
    # Check if .env file exists
    if [ ! -f .env ]; then
        log_error ".env file not found! Please mount your .env file or pass environment variables"
        log_info "You can mount it using: docker run -v \$(pwd)/.env:/var/www/html/.env:ro your-image"
        
        # If running with environment variables only (no .env file needed)
        if [ -n "$APP_KEY" ] && [ -n "$DB_CONNECTION" ]; then
            log_info "Running with environment variables only (no .env file)"
            return 0
        else
            log_error "Neither .env file nor required environment variables found!"
            exit 1
        fi
    fi
    
    # Generate app key if needed and .env exists
    if [ -f .env ]; then
        # Check if APP_KEY is empty or not set in .env
        if ! grep -q "^APP_KEY=base64:.\+" .env 2>/dev/null; then
            # If APP_KEY env var exists, use it
            if [ -n "$APP_KEY" ]; then
                log_info "Using APP_KEY from environment variable..."
                # Update .env with the APP_KEY from environment
                sed -i "s|^APP_KEY=.*|APP_KEY=$APP_KEY|" .env
            else
                log_info "Generating new application key..."
                php artisan key:generate --force
            fi
        else
            log_info "Application key already exists in .env"
        fi
    fi
}

# Function to handle Laravel optimization
optimize_laravel() {
    local env="${APP_ENV:-production}"
    
    # Only clear caches if they might be stale
    if [ "$CLEAR_CACHE" = "true" ] || [ ! -f bootstrap/cache/config.php ]; then
        log_info "Clearing caches..."
        
        # Use parallel execution for faster clearing
        {
            php artisan config:clear 2>/dev/null || true
            php artisan cache:clear 2>/dev/null || true
            php artisan view:clear 2>/dev/null || true
            php artisan route:clear 2>/dev/null || true
        } &
        wait
    fi
    
    # Cache configuration in production
    if [ "$env" = "production" ] && [ "$SKIP_CACHE" != "true" ]; then
        log_info "Optimizing for production..."
        
        # Cache configs (do this after migrations to ensure DB is ready)
        php artisan config:cache 2>/dev/null || {
            log_warn "Config caching failed, running without cache"
            php artisan config:clear 2>/dev/null || true
        }
        
        php artisan route:cache 2>/dev/null || {
            log_warn "Route caching failed, running without cache"
            php artisan route:clear 2>/dev/null || true
        }
        
        php artisan view:cache 2>/dev/null || {
            log_warn "View caching failed, running without cache"
            php artisan view:clear 2>/dev/null || true
        }
        
        # Event discovery if available
        php artisan event:cache 2>/dev/null || true
    else
        log_info "Skipping production optimizations (env: $env)"
    fi
}

# Function to handle database operations
handle_database() {
    # Skip if explicitly disabled
    if [ "$SKIP_MIGRATIONS" = "true" ]; then
        log_warn "Skipping database migrations (SKIP_MIGRATIONS=true)"
        return 0
    fi
    
    # Wait for database
    if ! wait_for_db; then
        if [ "$DB_REQUIRED" = "true" ]; then
            log_error "Database is required but not available. Exiting."
            exit 1
        else
            log_warn "Database not available, skipping migrations and seeds"
            return 1
        fi
    fi
    
    # Run migrations
    log_info "Running database migrations..."
    if ! php artisan migrate --force 2>/dev/null; then
        log_error "Migrations failed!"
        if [ "$FAIL_ON_MIGRATE_ERROR" = "true" ]; then
            exit 1
        fi
    fi
    
    # Handle seeders
    local seeder_flag="/var/www/html/storage/.seeders_run_${APP_ENV:-production}"
    
    if [ "$FORCE_SEED" = "true" ]; then
        log_info "Force seeding enabled, removing flag..."
        rm -f "$seeder_flag"
    fi
    
    if [ "$RUN_SEEDERS" = "true" ] && [ ! -f "$seeder_flag" ]; then
        log_info "Running database seeders..."
        if php artisan db:seed --force 2>/dev/null; then
            touch "$seeder_flag"
            log_info "Seeders completed successfully"
        else
            log_warn "Seeders failed, continuing anyway"
        fi
    elif [ -f "$seeder_flag" ]; then
        log_info "Seeders already run for $APP_ENV environment"
    fi
}

# Function for health check
health_check() {
    # Create a simple health check endpoint file if it doesn't exist
    if [ ! -f public/health ] && [ -w public ]; then
        echo "OK" > public/health
    fi
}

# Main execution
main() {
    log_info "Starting Laravel application setup..."
    
    # Setup in parallel where possible
    setup_storage &
    setup_env_file &
    wait
    
    # Database operations (must be sequential)
    handle_database
    
    # Laravel optimization
    optimize_laravel
    
    # Health check setup
    health_check
    
    log_info "Laravel setup complete!"
    
    # Execute command or start server
    if [ "$#" -eq 0 ]; then
        if [ "$APP_ENV" = "local" ] || [ "$APP_ENV" = "development" ]; then
            log_info "Starting Laravel development server..."
            exec php artisan serve --host=0.0.0.0 --port=8000
        else
            log_info "Starting production server..."
            # exec supervisord -c /etc/supervisord.conf
            exec php artisan serve --host=0.0.0.0 --port=8000
        fi
    else
        exec "$@"
    fi
}

# Run main function with all arguments
main "$@"