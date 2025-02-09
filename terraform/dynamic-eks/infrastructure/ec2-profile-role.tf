# Create an IAM role with S3 full access
resource "aws_iam_role" "s3_full_access_role" {
  name = "${var.project_name}-${var.environment}-s3-full-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the AmazonS3FullAccess policy to the IAM role
resource "aws_iam_role_policy_attachment" "s3_full_access_policy_attachment" {
  role       = aws_iam_role.s3_full_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Create an IAM instance profile for the role
resource "aws_iam_instance_profile" "s3_full_access_instance_profile" {
  name = "${var.project_name}-${var.environment}-instance-profile"
  role = aws_iam_role.s3_full_access_role.name
}
