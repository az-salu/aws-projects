# Create the Security Group for EC2 Instance Connect Endpoint
resource "aws_security_group" "eice_security_group" {
  name        = "${var.project_name}-${var.environment}-eice-sg"
  description = "Allow outbound SSH traffic on port 22 from the VPC CIDR"
  vpc_id      = aws_vpc.vpc.id

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eice-sg"
  }
}

# Create the Security Group for Data Migration Server
resource "aws_security_group" "data_migrate_server_security_group" {
  name        = "${var.project_name}-${var.environment}-data-migrate-server-sg"
  description = "Allow SSH access on port 22 via EICE security group"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "SSH access"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-data-migrate-server-sg"
  }
}

# Create the Security Group for Database
resource "aws_security_group" "database_security_group" {
  name        = "${var.project_name}-${var.environment}-database-sg"
  description = "Allow MySQL/Aurora access on port 3306"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "Allow MySQL/Aurora access"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.data_migrate_server_security_group.id]
  }

  ingress {
    description     = "MySQL/Aurora access"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-database-sg"
  }
}
