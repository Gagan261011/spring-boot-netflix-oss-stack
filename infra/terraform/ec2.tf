# Config Server EC2 Instance
resource "aws_instance" "config_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.internal.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-config-server"
    Service = "config-server"
  }

  user_data = base64encode(templatefile("${path.module}/templates/config-server-init.sh", {
    git_repo_url  = var.git_repo_url
    git_branch    = var.git_branch
    service_name  = "config-server"
    service_port  = 8888
    eureka_host   = ""
    config_host   = ""
    java_opts     = "-Xms256m -Xmx512m"
  }))
}

# Eureka Server EC2 Instance
resource "aws_instance" "eureka_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.internal.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-eureka-server"
    Service = "eureka-server"
  }

  user_data = base64encode(templatefile("${path.module}/templates/eureka-server-init.sh", {
    git_repo_url  = var.git_repo_url
    git_branch    = var.git_branch
    service_name  = "eureka-server"
    service_port  = 8761
    config_host   = aws_instance.config_server.private_ip
    java_opts     = "-Xms256m -Xmx512m"
  }))

  depends_on = [aws_instance.config_server]
}

# Core Backend EC2 Instance
resource "aws_instance" "core_backend" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.internal.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-core-backend"
    Service = "core-backend"
  }

  user_data = base64encode(templatefile("${path.module}/templates/service-init.sh", {
    git_repo_url   = var.git_repo_url
    git_branch     = var.git_branch
    service_name   = "core-backend"
    service_port   = 8082
    config_host    = aws_instance.config_server.private_ip
    eureka_host    = aws_instance.eureka_server.private_ip
    backend_host   = ""
    middleware_host = ""
    java_opts      = "-Xms256m -Xmx512m"
    requires_certs = "false"
  }))

  depends_on = [aws_instance.eureka_server]
}

# mTLS Middleware EC2 Instance
resource "aws_instance" "mtls_middleware" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.internal.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-mtls-middleware"
    Service = "mtls-middleware"
  }

  user_data = base64encode(templatefile("${path.module}/templates/middleware-init.sh", {
    git_repo_url   = var.git_repo_url
    git_branch     = var.git_branch
    service_name   = "mtls-middleware"
    service_port   = 8443
    config_host    = aws_instance.config_server.private_ip
    eureka_host    = aws_instance.eureka_server.private_ip
    backend_host   = aws_instance.core_backend.private_ip
    java_opts      = "-Xms256m -Xmx512m"
  }))

  depends_on = [aws_instance.core_backend]
}

# User BFF EC2 Instance
resource "aws_instance" "user_bff" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.internal.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-user-bff"
    Service = "user-bff"
  }

  user_data = base64encode(templatefile("${path.module}/templates/userbff-init.sh", {
    git_repo_url    = var.git_repo_url
    git_branch      = var.git_branch
    service_name    = "user-bff"
    service_port    = 8081
    config_host     = aws_instance.config_server.private_ip
    eureka_host     = aws_instance.eureka_server.private_ip
    middleware_host = aws_instance.mtls_middleware.private_ip
    java_opts       = "-Xms256m -Xmx512m"
  }))

  depends_on = [aws_instance.mtls_middleware]
}

# Cloud Gateway EC2 Instance
resource "aws_instance" "cloud_gateway" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.gateway.id, aws_security_group.internal.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-cloud-gateway"
    Service = "cloud-gateway"
  }

  user_data = base64encode(templatefile("${path.module}/templates/gateway-init.sh", {
    git_repo_url  = var.git_repo_url
    git_branch    = var.git_branch
    service_name  = "cloud-gateway"
    service_port  = 8080
    config_host   = aws_instance.config_server.private_ip
    eureka_host   = aws_instance.eureka_server.private_ip
    userbff_host  = aws_instance.user_bff.private_ip
    java_opts     = "-Xms256m -Xmx512m"
  }))

  depends_on = [aws_instance.user_bff]
}
