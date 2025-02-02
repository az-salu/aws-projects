# Create an SNS topic
resource "aws_sns_topic" "user_updates" {
  name = "${var.project_name}-${var.environment}-sns-topic"
}

# Create an SNS topic subscription
resource "aws_sns_topic_subscription" "notification_topic" {
  topic_arn = aws_sns_topic.user_updates.arn
  protocol  = "email"
  endpoint  = var.operator_email
}
