#!/bin/bash

# Enable debugging mode
set -x

# Update package lists
sudo su
sudo dnf update -y

# ================================================================
# Define environment variables
# ================================================================

export PROJECT_NAME=chatvia # the name of your project 
export S3_BUCKET_NAME=aosnote-project-web-files # the name of the s3 bucket containing your application code
export APPLICATION_CODE_FILE_NAME=chatvia-nodejs # the name of the zip file containing your application code 
export RDS_ENDPOINT=dev-rds-db.cu2idoemakwo.us-east-1.rds.amazonaws.com # your rds endpoint.amazonaws.com
export RDS_DB_NAME=applicationdb # your rds database name
export RDS_DB_USERNAME=azeezs # your rds database username
export DB_DB_PASSWORD=azeezs123 # your rds database password
export CAPTCHA_SITEKEY=6LcqBaQqAAAAACPNdpfIFPPto8u9IAR2MU5-mN63 # your actual site key from google
export CAPTCHA_SECRET=6LcqBaQqAAAAAN8pBxVwAMutp6RLxgC3r_-ZFsCP # your actual secret key from google

# ================================================================
# Install server dependencies
# ================================================================

# Install Node.js
curl -sL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install nodejs -y

# Install the MariaDB client (MySQL client)
sudo dnf install mariadb105 -y

# ================================================================
# Upload application code to EC2
# ================================================================

# Create a directory for project 
sudo mkdir "${PROJECT_NAME}"

# Download the app zip file from S3
sudo aws s3 cp s3://$S3_BUCKET_NAME/$APPLICATION_CODE_FILE_NAME.zip .

# Unzip the app code
sudo unzip $APPLICATION_CODE_FILE_NAME.zip

# Copy all files to the project directory
sudo cp -R $APPLICATION_CODE_FILE_NAME/. "${PROJECT_NAME}"/

# Remove the downloaded app zip file and unzip directory
sudo rm -rf $APPLICATION_CODE_FILE_NAME.zip $APPLICATION_CODE_FILE_NAME

# Navigate into the project directory
cd "${PROJECT_NAME}"

# ================================================================
# Install project (app) dependencies
# ================================================================

# Install dependencies for the project (from the package.json file)
sudo npm install -g npm@latest

# Install the MySQL client
sudo npm install mysql2

# Install PM2 (Process Manager 2) globally to keep the Node.js app running continuously
sudo npm install -g pm2

# Fix all vulnerabilities 
sudo npm audit fix

# ================================================================
# Update database and captcha value in the env file
# ================================================================

# Update variables in the config.env file
sudo sed -i "/^DB_HOST=/ s|=.*$|=${RDS_ENDPOINT}|" config.env
sudo sed -i "/^DB_DATABASE=/ s|=.*$|=${RDS_DB_NAME}|" config.env
sudo sed -i "/^DB_USERNAME=/ s|=.*$|=${RDS_DB_USERNAME}|" config.env
sudo sed -i "/^DB_PASSWORD=/ s|=.*$|=${RDS_DB_PASSWORD}|" config.env
sudo sed -i "/^CAPTCHA_SITEKEY=/ s|=.*$|=${CAPTCHA_SITEKEY}|" config.env
sudo sed -i "/^CAPTCHA_SECRET=/ s|=.*$|=${CAPTCHA_SECRET}|" config.env

# ================================================================================
# Use Nginx as a reverse proxy to forward traffic from port 80 to the application
# ================================================================================

# Install Nginx
sudo yum install nginx -y

# Add Nginx configuration
sudo bash -c 'cat > /etc/nginx/conf.d/chatvia.conf' << EOF
server {
    listen 80;

    location / {
        proxy_pass http://localhost:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# ================================================================
# Start the application
# ================================================================

# Restart Nginx
sudo systemctl restart nginx

# Start the application with PM2
sudo pm2 start app.js
