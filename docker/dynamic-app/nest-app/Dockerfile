# Use the latest version of the Amazon Linux base image
FROM amazonlinux:2023

# Avoid interactive prompts (if any)
ENV TERM=xterm \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Set the build argument directive
ARG PERSONAL_ACCESS_TOKEN
ARG GITHUB_USERNAME
ARG REPOSITORY_NAME
ARG DOMAIN_NAME
ARG RDS_ENDPOINT
ARG RDS_DB_NAME
ARG RDS_DB_USERNAME
ARG RDS_DB_PASSWORD

# Use the build argument to set environment variables 
ENV PERSONAL_ACCESS_TOKEN=$PERSONAL_ACCESS_TOKEN 
ENV GITHUB_USERNAME=$GITHUB_USERNAME
ENV REPOSITORY_NAME=$REPOSITORY_NAME
ENV DOMAIN_NAME=$DOMAIN_NAME
ENV RDS_ENDPOINT=$RDS_ENDPOINT
ENV RDS_DB_NAME=$RDS_DB_NAME
ENV RDS_DB_USERNAME=$RDS_DB_USERNAME
ENV RDS_DB_PASSWORD=$RDS_DB_PASSWORD

# Update all packages
RUN yum update -y

# Install Git
RUN dnf install -y git

# Install Apache, PHP and required extensions
RUN dnf install -y httpd php php-cli php-fpm php-mysqlnd php-bcmath php-ctype php-fileinfo php-json php-mbstring php-openssl php-pdo php-gd php-tokenizer php-xml php-curl

# Update memory_limit and max_execution_time in php.ini
RUN sed -i '/^memory_limit =/ s/=.*$/= 256M/' /etc/php.ini \
    && sed -i '/^max_execution_time =/ s/=.*$/= 300/' /etc/php.ini

# Enable mod_rewrite in Apache for .htaccess support
RUN sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf

# Navigate to web directory
WORKDIR /var/www/html

# Clone the GitHub repository
RUN git clone https://${PERSONAL_ACCESS_TOKEN}@github.com/${GITHUB_USERNAME}/${REPOSITORY_NAME}.git .

RUN ls -a  

# Set permissions for web and storage directories
RUN chmod -R 777 /var/www/html \
    && chmod -R 777 /var/www/html/bootstrap/cache/ \
    && chmod -R 777 /var/www/html/storage/

# Update .env variables
RUN sed -i "/^APP_URL=/ s|=.*$|=https://${DOMAIN_NAME}/|" .env \
    && sed -i "/^DB_HOST=/ s|=.*$|=${RDS_ENDPOINT}|" .env \
    && sed -i "/^DB_DATABASE=/ s|=.*$|=${RDS_DB_NAME}|" .env \
    && sed -i "/^DB_USERNAME=/ s|=.*$|=${RDS_DB_USERNAME}|" .env \
    && sed -i "/^DB_PASSWORD=/ s|=.*$|=${RDS_DB_PASSWORD}|" .env

# Replace AppServiceProvider.php
COPY AppServiceProvider.php app/Providers/AppServiceProvider.php

# Expose the default Apache and MySQL ports
EXPOSE 80 3306

# Copy the start-services script into the container
COPY start-services.sh /usr/local/bin/start-services.sh

# Ensure the script is executable
RUN chmod +x /usr/local/bin/start-services.sh

# Run the script to start both PHP-FPM and Apache
CMD ["/usr/local/bin/start-services.sh"]
