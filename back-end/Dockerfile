# =======================
# Base PHP Image with Extensions (Cached)
# =======================
FROM php:8.3-fpm-alpine3.20 AS php-extensions

# Install all dependencies and PHP extensions once
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
    # Runtime dependencies
    curl \
    nginx \
    supervisor \
    bash \
    git \
    zip \
    unzip \
    icu-libs \
    oniguruma \
    postgresql-libs \
    libzip \
    libpng \
    libjpeg-turbo \
    libwebp \
    freetype \
    shadow \
    # Build dependencies (marked virtual for easy removal)
    && apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    icu-dev \
    oniguruma-dev \
    postgresql-dev \
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    libwebp-dev \
    freetype-dev \
    # Configure and install PHP extensions
    && docker-php-ext-configure gd \
        --with-jpeg \
        --with-freetype \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        gd \
        zip \
        exif \
        mbstring \
        intl \
        opcache \
    # Install Redis extension
    && pecl install redis \
    && docker-php-ext-enable redis \
    # Clean up build dependencies
    && apk del .build-deps \
    && rm -rf /tmp/pear

# =======================
# Composer Dependencies
# =======================
FROM php-extensions AS composer-stage

# Install Composer
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Copy composer files first for better caching
COPY composer.json composer.lock ./

# Use BuildKit cache mount for composer cache
RUN --mount=type=cache,target=/root/.composer/cache \
    composer install \
    # --no-dev \
    --prefer-dist \
    --no-interaction \
    --optimize-autoloader \
    --no-scripts \
    --no-autoloader

# Copy app source
COPY . .

# Generate optimized autoloader after copying all files
RUN composer dump-autoload --optimize --classmap-authoritative

# =======================
# Node Dependencies & Assets
# =======================
FROM node:18-alpine AS node-stage

WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Use BuildKit cache mount for npm cache
RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline --no-audit

# Copy necessary files for building
COPY . .

# Copy vendor if needed for frontend build
COPY --from=composer-stage /app/vendor ./vendor

# Build assets
RUN npm run build

# =======================
# Production Final Image
# =======================
FROM php-extensions AS production

WORKDIR /var/www/html

# Create non-root user
RUN addgroup -g 1001 -S clms \
    && adduser -S clms -u 1001 -G clms

# Set environment
ENV APP_ENV=production \
    APP_DEBUG=false

# Copy nginx config first (rarely changes)
# COPY ./dockerfiles/nginx/default.conf /etc/nginx/http.d/default.conf

# COPY ./dockerfiles/supervisord.conf /etc/supervisord.conf

# Copy entrypoint
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Prepare Nginx log directory with correct ownership
# RUN mkdir -p /var/lib/nginx/logs \
#     && chown -R clms:clms /var/lib/nginx

# Copy application code with correct ownership
COPY --chown=clms:clms . .

# Copy vendor from composer stage
COPY --from=composer-stage --chown=clms:clms /app/vendor ./vendor

# Copy built frontend assets
COPY --from=node-stage --chown=clms:clms /app/public/build ./public/build

# Set permissions in a single layer
RUN chmod -R 755 storage bootstrap/cache

# Optional: Pre-cache Laravel (uncomment if needed)
# RUN php artisan config:cache \
#     && php artisan route:cache \
#     && php artisan view:cache \
#     && php artisan event:cache

USER clms

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
# CMD ["supervisord", "-c", "/etc/supervisord.conf"]

CMD ["/entrypoint.sh"]