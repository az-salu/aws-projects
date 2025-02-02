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

# Create the Security Group for Application Load Balancer
resource "aws_security_group" "alb_security_group" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Allow HTTP/HTTPS access on ports 80/443"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# Create the Security Group for Application Server
resource "aws_security_group" "app_server_security_group" {
  name        = "${var.project_name}-${var.environment}-app-server-sg"
  description = "Allow HTTP/HTTPS access on ports 80/443 via ALB SG and SSH via EICE SG"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "Allow HTTP access"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_security_group.id]
  }

  ingress {
    description     = "Allow HTTPS access"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_security_group.id]
  }

  ingress {
    description     = "Allow SSH access"
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
    Name = "${var.project_name}-${var.environment}-app-server-sg"
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
    security_groups = [aws_security_group.app_server_security_group.id]
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
