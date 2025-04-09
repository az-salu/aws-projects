How to host an HTML web application on AWS EC2
## Course Overview
This course will guide you through the process of hosting a simple HTML web application on AWS EC2. You will learn how to set up an EC2 instance, configure security groups, and deploy your application.
    - Create an S3 bucket and upload the application code
    - Delete the default VPC and recreate it
    - Create a key pair and move the private key to the `.ssh` directory
    - Create a security group and open ports 22 and 80 for inbound traffic
    - Create an IAM role with S3 Full Access permission
    - Launch an EC2 instance
    - SSH into the EC2 instance (Windows)
    - SSH into the EC2 instance (Mac)
    - Application Installation Commands Explained
    - Install the application on the EC2 instance
    - Clean up: Delete the EC2 instance and security group

## Naming convention for the resources
aosnote-dev-s3-bucket
dev-key-pair
dev-sg
dev-s3-full-access-role
dev-ec2

## Assignments
Using the knowledge gained from this course, complete the following tasks to deploy the application on an EC2 instance in your default VPC:

1. **Manual Installation**:  
    - Download the application code from the video description.  
    - Manually install the application on an EC2 instance.

2. **Automated Installation with S3**:  
    - Create a script to install the application on an EC2 instance using EC2 user data.  
    - Ensure the script downloads the application code from an S3 bucket.

3. **Automated Installation with GitHub**:  
    - Create another script to install the application on an EC2 instance using EC2 user data.  
    - Ensure the script downloads the application code from a GitHub repository.  
    - If you do not have a GitHub repository, use the application code download link provided by Azeez in the video description.

These assignments will help reinforce your understanding of deploying applications on AWS EC2.
