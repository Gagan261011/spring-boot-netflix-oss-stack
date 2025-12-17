# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get first available subnet
data "aws_subnet" "selected" {
  id = data.aws_subnets.default.ids[0]
}

# Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for internal communication
resource "aws_security_group" "internal" {
  name        = "${var.project_name}-internal-sg"
  description = "Security group for internal service communication"
  vpc_id      = data.aws_vpc.default.id

  # Allow all traffic within the security group
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # SSH access from admin CIDR
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-internal-sg"
  }
}

# Security Group for Gateway (public facing)
resource "aws_security_group" "gateway" {
  name        = "${var.project_name}-gateway-sg"
  description = "Security group for API Gateway"
  vpc_id      = data.aws_vpc.default.id

  # Gateway port 8080 open to public
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access from admin CIDR
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Allow internal traffic
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.internal.id]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-gateway-sg"
  }
}

# Security Group for Eureka (public facing for dashboard)
resource "aws_security_group" "eureka" {
  name        = "${var.project_name}-eureka-sg"
  description = "Security group for Eureka Dashboard"
  vpc_id      = data.aws_vpc.default.id

  # Eureka port 8761 open to admin
  ingress {
    from_port   = 8761
    to_port     = 8761
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  tags = {
    Name = "${var.project_name}-eureka-sg"
  }
}
