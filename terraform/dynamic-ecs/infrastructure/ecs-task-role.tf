# Define the IAM policy document to allow ECS tasks to assume a role
data "aws_iam_policy_document" "ecs_task_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    effect = "Allow"
  }
}

# Create the ECS task role
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-${var.environment}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json
}

# Attach the AmazonSSMFullAccess policy to the ECS task role
resource "aws_iam_role_policy_attachment" "ecs_task_role_ssm_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

# Attach the AmazonECSTaskExecutionRolePolicy policy to the ECS task role
resource "aws_iam_role_policy_attachment" "ecs_task_role_ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
