#!/bin/sh

php artisan key:generate
php artisan migrate --force
php artisan db:seed --force 

# Then start Laravel server
php artisan serve --host=0.0.0.0 --port=8000

