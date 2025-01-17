#!/bin/bash

# Enable debugging mode
set -x

# Update all packages
sudo yum update -y

# ================================================================
# Define environment variables
# ================================================================

# Define environment variables
export PROJECT_NAME=nest # the name of your project 
export ENVIRONMENT=dev # the environment that the app will be deployed 
export RECORD_NAME=www # the sub-domain name
export DOMAIN_NAME=aosnotes77.com # the domain name 
export S3_BUCKET_NAME=aosnote-project-web-files # the name of the s3 bucket containing your application code
export APPLICATION_CODE_FILE_NAME=nest # the name of the zip file containing your application code 
export RDS_ENDPOINT=dev-rds-db.cu2idoemakwo.us-east-1.rds.amazonaws.com # your rds endpoint.amazonaws.com
export RDS_DB_NAME=applicationdb # your rds database name
export RDS_DB_USERNAME=azeezs # your rds database username
export DB_DB_PASSWORD=azeezs123 # your rds database password

# ================================================================
# Install server dependencies
# ================================================================

# Install PHP 8 and required extensions
sudo dnf install -y httpd php php-cli php-fpm php-mysqlnd php-bcmath php-ctype php-fileinfo php-json php-mbstring php-openssl php-pdo php-gd php-tokenizer php-xml php-curl

# Update PHP settings for memory and execution time
sudo sed -i '/^memory_limit =/ s/=.*$/= 256M/' /etc/php.ini
sudo sed -i '/^max_execution_time =/ s/=.*$/= 300/' /etc/php.ini

# Enable mod_rewrite in Apache for .htaccess support
sudo sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf

# ================================================================
# Upload application code to EC2
# ================================================================

# Download the app zip file from S3
sudo aws s3 cp s3://${S3_BUCKET_NAME}/${APPLICATION_CODE_FILE_NAME}.zip /var/www/html

# Navigate to web directory
cd /var/www/html

# Unzip the app code
sudo unzip ${APPLICATION_CODE_FILE_NAME}.zip

# Copy all files from 'nest' to web root
sudo cp -R ${APPLICATION_CODE_FILE_NAME}/. /var/www/html/

# Remove the 'nest' directory and zip file
sudo rm -rf ${APPLICATION_CODE_FILE_NAME} ${APPLICATION_CODE_FILE_NAME}.zip

# ================================================================
# Set permissions for directories
# ================================================================

# Set permissions for web and storage directories
sudo chmod -R 777 /var/www/html
sudo chmod -R 777 /var/www/html/bootstrap/cache/
sudo chmod -R 777 /var/www/html/storage/

# ================================================================
# Update the .env and AppServiceProvider.php file
# ================================================================

# Update .env variables
sudo sed -i "/^APP_NAME=/ s|=.*$|=${PROJECT_NAME}-${ENVIRONMENT}|" .env
sudo sed -i "/^APP_URL=/ s|=.*$|=https://${RECORD_NAME}.${DOMAIN_NAME}/|" .env
sudo sed -i "/^DB_HOST=/ s|=.*$|=${RDS_ENDPOINT}|" .env
sudo sed -i "/^DB_DATABASE=/ s|=.*$|=${RDS_DB_NAME}|" .env
sudo sed -i "/^DB_USERNAME=/ s|=.*$|=${RDS_DB_USERNAME}|" .env
sudo sed -i "/^DB_PASSWORD=/ s|=.*$|=${RDS_DB_PASSWORD}|" .env

# Replace AppServiceProvider.php
sudo aws s3 cp s3://aosnote-app-service-provider-files/nest-AppServiceProvider.php /var/www/html/app/Providers/AppServiceProvider.php

# Restart Apache
sudo service httpd restart
