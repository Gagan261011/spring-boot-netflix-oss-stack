# Sanity Test Runner - Runs after all services are up
resource "null_resource" "wait_for_services" {
  depends_on = [aws_instance.cloud_gateway]

  provisioner "local-exec" {
    command = <<-EOT
      Write-Host "Waiting for all services to be fully ready..."
      Write-Host "This takes approximately 15-20 minutes for all services to deploy and start."
      Write-Host "Gateway Public IP: ${aws_instance.cloud_gateway.public_ip}"
      Start-Sleep -Seconds 900
      Write-Host "Services should be ready now."
    EOT
    interpreter = ["PowerShell", "-Command"]
  }
}

resource "null_resource" "run_sanity_tests" {
  depends_on = [null_resource.wait_for_services]

  triggers = {
    gateway_ip = aws_instance.cloud_gateway.public_ip
  }

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.module}/../../scripts/sanity/run_sanity.ps1 -GatewayIP ${aws_instance.cloud_gateway.public_ip}"
    interpreter = ["PowerShell", "-Command"]
    working_dir = path.module
  }
}
