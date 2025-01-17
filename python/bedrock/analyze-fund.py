# Import modules
import boto3
import csv
import json

# Create a Bedrock client using boto3 to interact with AWS Bedrock's runtime service
bedrock_client = boto3.client('bedrock-runtime')

# List of all holdings files to process
holdings_files = [
    "oct_holdings_2024.csv",
    "nov_holdings_2024.csv"
]

# Converts CSV file content into a string with pipe separators between values
def format_holdings(filename):
    with open(filename, mode="r", newline="", encoding="utf-8") as file:
        csv_reader = csv.reader(file)
        return "\n".join(" | ".join(row) for row in csv_reader)

# Process all files in one line
formatted_holdings = {filename: format_holdings(filename) for filename in holdings_files}

# Construct the prompt configuration using the JSON string
prompt_config = {
    "anthropic_version": "bedrock-2023-05-31",
    "temperature": 1,
    "top_p": 0.999,
    "top_k": 250,
    "max_tokens": 2000, 
    "stop_sequences": ["\n\nHuman:"], 
    "messages": [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "I have provided you with two documents named formatted_jan_holding and formatted_feb_holding. Please compare these two documents and create a list of the top 30 holdings whose share count has changed between January and February. For each holding, please only provide the holdings name, ticker symbol and the difference in shares between January and February.:"},
                {"type": "text", "text": formatted_holdings["oct_holdings_2024.csv"]}, 
                {"type": "text", "text": formatted_holdings["nov_holdings_2024.csv"]},
            ],
        }
    ],
}

# Prepare the request configuration for an AI model API call
body = json.dumps(prompt_config)
contentType = "application/json"
accept = "application/json"
modelId = "anthropic.claude-3-haiku-20240307-v1:0"

# Invokes the specified Bedrock model
response = bedrock_client.invoke_model(
    body=body, 
    contentType=contentType,
    accept=accept,
    modelId=modelId,  
)

# Parse the JSON response body from a bytes/string format into a Python dictionary/object
response_body = json.loads(response.get("body").read())

# Extract the text content from the first item in the 'content' array of the response
results = response_body.get("content")[0].get("text")

# Specify the filename you want to write to
filename = "findings.txt"

# Open the file in write mode ('w') and write the results to it
with open(filename, "w") as file:
    file.write(results)
