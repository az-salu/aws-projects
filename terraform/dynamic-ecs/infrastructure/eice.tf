# create an ec2 instance connect endpoint
resource "aws_ec2_instance_connect_endpoint" "instance_connect_endpoint" {
  subnet_id          = aws_subnet.private_data_subnet_az1.id
  security_group_ids = [aws_security_group.eice_security_group.id]
  tags = {
    Name = "${var.project_name}-${var.environment}-eice"
  }
}
