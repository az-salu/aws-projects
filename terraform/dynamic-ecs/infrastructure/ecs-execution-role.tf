# Define the IAM policy document to allow ECS service to assume a role
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Define the IAM policy document for ECS task execution
data "aws_iam_policy_document" "ecs_task_execution_policy_document" {
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "arn:aws:s3:::${var.env_file_bucket_name}/${var.project_name}.env"
    ]
  }

  statement {
    actions = [
      "s3:GetBucketLocation"
    ]

    resources = [
      "arn:aws:s3:::${var.env_file_bucket_name}"
    ]
  }
}

# Create the IAM policy for ECS task execution
resource "aws_iam_policy" "ecs_task_execution_policy" {
  name   = "${var.project_name}-${var.environment}-ecs-task-execution-role-policy"
  policy = data.aws_iam_policy_document.ecs_task_execution_policy_document.json
}

# Create the IAM ECS task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.project_name}-${var.environment}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

# Attach the ECS task execution policy to the IAM role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_execution_policy.arn
}
