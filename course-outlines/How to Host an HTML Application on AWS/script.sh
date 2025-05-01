# Create an environment variable for the S3 zip file
export S3_URI=""

# Update the packages on the EC2 instance
sudo yum update -y

# Install the Apache HTTP Server
sudo yum install -y httpd

# Change to the Apache web root directory
cd /var/www/html

# Remove any existing files
sudo rm -rf *

# Download the zip file from the S3 bucket
sudo aws s3 cp "$S3_URI" .

# Unzip the downloaded file
sudo unzip jupiter.zip

# Copy the contents to the html directory
sudo cp -R jupiter/. .

# Clean up zip file and extracted folder
sudo rm -rf jupiter jupiter.zip

# Enable and start Apache service
sudo systemctl enable httpd
sudo systemctl start httpd
