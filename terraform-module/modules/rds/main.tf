# create database subnet group
resource "aws_db_subnet_group" "database_subnet_group" {
  name        = "${var.project_name}-${var.environment}-database-subnets"
  subnet_ids  = [var.private_data_subnet_az1_id, var.private_data_subnet_az2_id]
  description = "subnets for database instance"

  tags = {
    Name = "${var.project_name}-${var.environment}-database-subnets"
  }
}

# create the rds instance
resource "aws_db_instance" "database_instance" {
  engine                 = var.engine
  engine_version         = var.engine_version
  multi_az               = var.multi_az_deployment
  identifier             = var.database_instance_identifier
  username               = var.rds_db_username
  password               = var.rds_db_password
  db_name                = var.rds_db_name
  instance_class         = var.database_instance_class
  allocated_storage      = var.allocated_storage
  db_subnet_group_name   = aws_db_subnet_group.database_subnet_group.name
  vpc_security_group_ids = [var.database_security_group_id]
  availability_zone      = var.availability_zone_1
  skip_final_snapshot    = var.skip_final_snapshot
  publicly_accessible    = var.publicly_accessible
}
