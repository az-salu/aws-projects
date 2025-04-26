# Create an Environment Variable for the Blob SAS URL
export BLOB_SAS_URL=""

# Update the packages on the VM
sudo apt update

# Install unzip and Apache
sudo apt install unzip apache2 -y

# Change to the html directory
cd /var/www/html

# Remove any existing files
sudo rm -rf *

# Download the zip file
wget -O jupiter.zip "$BLOB_SAS_URL"

# Unzip the downloaded file
sudo unzip jupiter.zip

# Copy the contents to the html directory
sudo cp -R jupiter/. .

# Clean up zip and directory
sudo rm -rf jupiter jupiter.zip

# Enable and start Apache service
sudo systemctl enable apache2
sudo systemctl start apache2
