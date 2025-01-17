# create the ec2 instance that will be used to migrate sql data
resource "aws_instance" "data_migrate_ec2" {
  ami                    = var.amazon_linux_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = var.private_app_subnet_az1_id
  vpc_security_group_ids = [var.app_server_security_group_id]
  iam_instance_profile   = var.ec2_instance_profile_role_name

  user_data = base64encode(templatefile("${path.module}/../../${var.project_directory}/migrate-sql.sh.tpl", {
    RDS_ENDPOINT    = var.rds_endpoint
    RDS_DB_NAME     = var.rds_db_name
    RDS_DB_USERNAME = var.rds_db_username
    RDS_DB_PASSWORD = var.rds_db_password
  }))

  tags = {
    Name = "${var.project_name}-${var.environment}-data-migrate-ec2"
  }
}
