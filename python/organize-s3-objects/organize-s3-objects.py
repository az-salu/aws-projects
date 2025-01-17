# Import modules
import boto3
from datetime import datetime

# Get today's date using datetime
today = datetime.today()

# Format today's date as YYYYMMDD
todays_date = today.strftime("%Y%m%d")

# Initialize S3 client using boto3
s3_client = boto3.client('s3')

# Define the target S3 bucket name
bucket_name = "aosnote-organize-s3-objects"

# List all objects in the bucket
list_objects_response = s3_client.list_objects_v2(Bucket=bucket_name)

# Extract the Contents section from the response which contains object details
get_contents = list_objects_response.get("Contents")

# Initialize empty list to store all object and folder names
get_all_s3_object_and_folder_names = []

# Loop through all objects and extract their keys (names)
for item in get_contents:
    s3_object_name = item.get("Key")

    get_all_s3_object_and_folder_names.append(s3_object_name)

# Create directory name with today's date (YYYYMMDD/)
directory_name = todays_date + "/"

# Check if today's directory doesn't exist, create it
if directory_name not in get_all_s3_object_and_folder_names:
    s3_client.put_object(Bucket=bucket_name, Key=(directory_name))

# Loop through all objects to organize them
for item in get_contents:
    # Get object's creation date formatted as YYYYMMDD/
    object_creation_date = item.get("LastModified").strftime("%Y%m%d") + "/"
    # Get object's name (key)
    object_name = item.get("Key")

    # If object was created today and is not already in a folder (no "/" in name)
    if object_creation_date == directory_name and "/" not in object_name:
        # Copy object to today's directory
        s3_client.copy_object(
            Bucket=bucket_name, 
            CopySource=bucket_name+"/"+object_name, 
            Key=directory_name+object_name
        )

        # Delete original object after copying
        s3_client.delete_object(Bucket=bucket_name, Key=object_name)
