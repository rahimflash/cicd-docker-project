#!/bin/sh

# Clear existing caches
php artisan config:clear
php artisan cache:clear  
php artisan route:clear
php artisan view:clear

# Rebuild caches for production
if [ "$APP_ENV" = "production" ]; then
    php artisan config:cache
    php artisan route:cache  
    php artisan view:cache
fi
# Run migrations and seed the database
php artisan key:generate
php artisan migrate --force
php artisan db:seed --force 

# Then start Laravel server
php artisan serve --host=0.0.0.0 --port=8000

