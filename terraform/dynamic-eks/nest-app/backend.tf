# Configure Terraform to use S3 for state storage and DynamoDB for state locking
terraform {
  backend "s3" {
    bucket         = "aosnote-terraform-remote-state"
    key            = "nest-eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
  }
}
