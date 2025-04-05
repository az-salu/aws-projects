# Create an S3 bucket to store the build artifacts
resource "aws_s3_bucket" "codebuild_bucket" {
  bucket = "${var.project_name}-${var.environment}-codebuild-artifacts-bucket"
}

# Create IAM role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-${var.environment}-codebuild-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

# Create IAM policy for CodeBuild role
resource "aws_iam_role_policy" "codebuild_policy" {
  role = aws_iam_role.codebuild_role.name
  name = "${var.project_name}-${var.environment}-codebuild-service-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "${aws_s3_bucket.codebuild_bucket.arn}",
          "${aws_s3_bucket.codebuild_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "${var.secret_arn}"
        ]
      }
    ]
  })
}

# CodeBuild project
resource "aws_codebuild_project" "codebuild_project" {
  name           = "${var.project_name}-${var.environment}-codebuild-project"
  description    = "${var.project_name} ${var.environment} codebuild project"
  service_role   = aws_iam_role.codebuild_role.arn
  build_timeout  = 60 # in minutes
  source_version = var.source_branch

  # Define the build artifacts for the CodeBuild project
  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.codebuild_bucket.bucket
    name      = "output"
  }

  # Define the build environment for the CodeBuild project
  environment {
    type            = var.build_environment_type
    compute_type    = var.build_compute_type
    image           = var.build_image
    privileged_mode = false # Set to true if you need Docker in Docker

    # Define environment variables from Secrets Manager
    environment_variable {
      name  = "AWS_REGION:"
      value = "${var.region}"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "GITHUB_USERNAME"
      value = "${var.github_username}"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "AWS_ACCESS_KEY_ID"
      value = "${var.secret_arn}:aws_access_key_id::"
      type  = "SECRETS_MANAGER"
    }

    environment_variable {
      name  = "AWS_SECRET_ACCESS_KEY"
      value = "${var.secret_arn}:aws_secret_access_key::"
      type  = "SECRETS_MANAGER"
    }

    environment_variable {
      name  = "ECR_REGISTRY"
      value = "${var.secret_arn}:ecr_registry::"
      type  = "SECRETS_MANAGER"
    }

    environment_variable {
      name  = "PERSONAL_ACCESS_TOKEN"
      value = "${var.secret_arn}:personal_access_token::"
      type  = "SECRETS_MANAGER"
    }

    environment_variable {
      name  = "RDS_DB_NAME"
      value = "${var.secret_arn}:db_name::"
      type  = "SECRETS_MANAGER"
    }

    environment_variable {
      name  = "RDS_DB_PASSWORD"
      value = "${var.secret_arn}:password::"
      type  = "SECRETS_MANAGER"
    }

    environment_variable {
      name  = "RDS_DB_USERNAME"
      value = "${var.secret_arn}:username::"
      type  = "SECRETS_MANAGER"
    }
  }

  # Define the source configuration for the CodeBuild project
  source {
    type            = var.source_type
    location        = var.source_location
    git_clone_depth = 1

    buildspec = var.buildspec_file

    # Specify the branch to build from
    git_submodules_config {
      fetch_submodules = true
    }
  }

  # Define log config
  logs_config {
    cloudwatch_logs {
      group_name  = "${var.project_name}-${var.environment}-codebuild-log-group"
      stream_name = "${var.project_name}-${var.environment}-codebuild-log-stream"
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
