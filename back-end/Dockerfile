# Multi-stage Dockerfile for Laravel Backend (CLMS)
# Stage 1: Composer Dependencies
FROM composer:2.7 AS composer-stage

WORKDIR /app

# Copy composer files
COPY composer.json ./

# Debug: Show PHP version and composer info
RUN php -v
RUN composer --version
# RUN composer diagnose

# Try to validate composer.json first
RUN composer validate --no-check-all --strict

# Update composer to latest version
RUN composer self-update

# Clear composer cache
RUN composer clear-cache

# Install dependencies with more verbose output and better error handling
RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-interaction \
    --optimize-autoloader \
    --no-scripts \
    --verbose \
    || (echo "Composer install failed. Trying with --ignore-platform-reqs..." && \
        composer install \
        --no-dev \
        --prefer-dist \
        --no-interaction \
        --optimize-autoloader \
        --no-scripts \
        --ignore-platform-reqs \
        --verbose)


# Generate autoloader
COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative

# Stage 2: Node Dependencies and Asset Building
FROM node:18-alpine AS node-stage

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install Node dependencies
RUN npm ci --only=production

# Copy source files for asset building
COPY . .
COPY --from=composer-stage /app/vendor ./vendor

# Build assets with Vite
RUN npm run build

# Stage 3: PHP Runtime
FROM php:8.3-fpm-alpine3.20 AS php-base

# Install system dependencies
RUN apk add --no-cache \
    curl \
    nginx \
    supervisor \
    zip \
    unzip \
    libpng-dev \
    libjpeg-turbo-dev \
    libzip-dev \
    icu-dev \
    oniguruma-dev \
    postgresql-dev \
    && rm -rf /var/cache/apk/*

# Install PHP extensions
RUN docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        gd \
        zip \
        exif \
        mbstring \
        intl \
        opcache

# Install Redis extension
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps

# Configure PHP for production
# COPY ./docker/php/php.ini /usr/local/etc/php/conf.d/99-custom.ini
# COPY ./docker/php/opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# Stage 4: Final Production Image
FROM php-base AS production

# Create application user
RUN addgroup -g 1001 -S clms && \
    adduser -S clms -u 1001 -G clms

# Set working directory
WORKDIR /var/www/html

# Copy application code
COPY --chown=clms:clms . .

# Copy vendor from composer stage
COPY --from=composer-stage --chown=clms:clms /app/vendor ./vendor

# Copy built assets from node stage
COPY --from=node-stage --chown=clms:clms /app/public/build ./public/build

# Copy configuration files
# COPY ./docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./dockerfiles/nginx/default.conf /etc/nginx/http.d/default.conf
# COPY ./docker/supervisor/supervisord.conf /etc/supervisord.conf
COPY ./entrypoint.sh /entrypoint.sh

# Set permissions
RUN chown -R clms:clms /var/www/html \
    && chmod -R 755 /var/www/html/storage \
    && chmod -R 755 /var/www/html/bootstrap/cache \
    && chmod +x /entrypoint.sh

# Create necessary directories
RUN mkdir -p /var/log/nginx \
    && mkdir -p /var/log/supervisor \
    && mkdir -p /run/nginx \
    && chown -R clms:clms /var/log/nginx \
    && chown -R clms:clms /var/log/supervisor \
    && chown -R clms:clms /run/nginx

# Switch to application user
USER clms

# Optimize Laravel for production
RUN php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache
    
# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["supervisord", "-c", "/etc/supervisord.conf"]