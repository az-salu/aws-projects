# macOS / Linux (Terminal)

# Move the key to the Home directory
mv ~/Downloads/dev-vm-key.pem ~/dev-vm-key.pem

# Set proper file permissions (very important for SSH to work)
chmod 600 ~/dev-vm-key.pem

# Verify if the key exists in the Home directory
ls -l ~/dev-vm-key.pem