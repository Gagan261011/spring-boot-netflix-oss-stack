# Sanity Test Runner - Runs after all services are up
resource "null_resource" "wait_for_services" {
  depends_on = [aws_instance.cloud_gateway]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for all services to be fully ready..."
      sleep 300
      echo "Services should be ready now."
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "run_sanity_tests" {
  depends_on = [null_resource.wait_for_services]

  triggers = {
    gateway_ip = aws_instance.cloud_gateway.public_ip
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}/../../scripts/sanity
      chmod +x run_sanity.sh
      ./run_sanity.sh ${aws_instance.cloud_gateway.public_ip}
    EOT
    interpreter = ["bash", "-c"]
    working_dir = path.module
  }
}

# For Windows users, alternative using PowerShell
resource "null_resource" "run_sanity_tests_windows" {
  count      = 0 # Set to 1 if running on Windows
  depends_on = [null_resource.wait_for_services]

  triggers = {
    gateway_ip = aws_instance.cloud_gateway.public_ip
  }

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.module}/../../scripts/sanity/run_sanity.ps1 -GatewayIP ${aws_instance.cloud_gateway.public_ip}"
    interpreter = ["PowerShell", "-Command"]
  }
}
