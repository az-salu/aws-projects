=============================================================================
Reference Links
=============================================================================
Investment Resources
- [Holdings details](https://advisors.vanguard.com/investments/products/voog/vanguard-sp-500-growth-etf#performance)

AWS Documentation
- [Boto3 invoke_model](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/bedrock-runtime/client/invoke_model.html)

- [Amazon Bedrock model IDs](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html)

- [Anthropic version](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-anthropic-claude-messages.html#model-parameters-anthropic-claude-messages-request-response)

- [Bedrock Information](https://aws.amazon.com/blogs/aws/anthropics-claude-3-haiku-model-is-now-available-in-amazon-bedrock/)

Development Tools
- [Homebrew formulae](https://formulae.brew.sh/)

=============================================================================
Troubleshooting Guide
=============================================================================

IPykernel Installation

To set up IPykernel in a virtual environment:

```bash
# Navigate to your project directory - replace with your actual path
cd path/to/project-directory

# Create a new virtual environment named 'venv' in your project directory
python3 -m venv venv

# Activate the virtual environment - this ensures pip installs packages in the venv
source venv/bin/activate

# Install the ipykernel package which allows Jupyter notebooks to use this Python environment
pip install ipykernel

# Register this environment as a Jupyter kernel named 'azeez-project'
python -m ipykernel install --user --name=aosnote-venv

# After running these commands:
# 1. Go back to VS Code
# 2. Click "Select Kernel" in your notebook
# 3. Choose "azeez-project" from the kernel list
```