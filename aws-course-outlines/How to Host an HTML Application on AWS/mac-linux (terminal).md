# macOS / Linux (Terminal)

# Move the key to the Home directory
mv ~/Downloads/dev-ec2-key.pem ~/dev-ec2-key.pem

# Set proper file permissions (very important for SSH to work)
chmod 600 ~/dev-ec2-key.pem

# Verify if the key exists in the Home directory
ls -l ~/dev-ec2-key.pem