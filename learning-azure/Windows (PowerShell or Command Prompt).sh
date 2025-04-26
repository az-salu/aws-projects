# Windows (PowerShell or Command Prompt)

# Move the key to the Home directory
move "$HOME\Downloads\dev-vm-key.pem" "$HOME\dev-vm-key.pem"


# Verify if the key exists in the Home directory
Test-Path "$HOME\dev-vm-key.pem"