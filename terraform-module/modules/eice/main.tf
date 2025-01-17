# create an ec2 instance connect endpoint
resource "aws_ec2_instance_connect_endpoint" "instance_connect_endpoint" {
  subnet_id          = var.private_data_subnet_az1_id
  security_group_ids = [var.eice_security_group_id]
  tags = {
    Name = "${var.project_name}-${var.environment}-eice"
  }
}
