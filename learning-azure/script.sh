# Create an Environment Variable for the Blob SAS URL
export BLOB_SAS_URL=""

# Update the package list
sudo apt update

# Install Apache
sudo apt install apache2 -y

# # Install unzip if not already installed
# sudo apt install unzip -y

# Change to the html directory where the website files will be placed
cd /var/www/html

# Download the zip file from the specified URL
wget "$BLOB_SAS_URL"

# Unzip the downloaded zip file
unzip jupiter.zip

# Copy the contents of the 'jupiter' directory to the current directory
cp -R jupiter/. .

# Remove the 'jupiter' directory and the zip file to clean up
rm -rf jupiter jupiter.zip

# Enable Apache to start on boot
sudo systemctl enable apache2

# Start the Apache service
sudo systemctl start apache2
