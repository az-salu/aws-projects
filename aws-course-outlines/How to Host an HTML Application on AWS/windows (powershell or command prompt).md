# Windows (PowerShell or Command Prompt)

# Move the key to the Home directory
move "$HOME\Downloads\dev-ec2-key.pem" "$HOME\dev-ec2-key.pem"

# Verify if the key exists in the Home directory
Test-Path "$HOME\dev-ec2-key.pem"