#!/bin/bash

# Create a environment variable to store the S3 URI of the zip file containing the website files
export S3_URI=s3://aosnote-project-web-files/jupiter.zip

# Switch to the root user to gain full administrative privileges
sudo su

# Update all installed on the EC2 instance to their latest versions
yum update -y

# Install Apache HTTP Server
yum install -y httpd

# Change the current working directory to the Apache web root
cd /var/www/html

# Download the website files from the S3 bucket to the Apache web root directory
aws s3 cp $S3_URI .

# Unzip the downloaded zip file to extract the website files
unzip jupiter.zip

# Copy all files from the 'jupiter' directory to the web root directory
cp -R jupiter/. .

# Remove the 'jupiter' directory and the zip file to clean up
rm -rf jupiter jupiter.zip

# Enable the Apache HTTP Server to start automatically at system boot
systemctl enable httpd 

# Start the Apache HTTP Server to serve web content
systemctl start httpd
