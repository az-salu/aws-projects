# Store the Terraform state file in S3 and lock with DynamoDB
terraform {
  backend "s3" {
    bucket         = "aosnote-terraform-remote-state"
    key            = "codebuild/nest-ecs/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
  }
}