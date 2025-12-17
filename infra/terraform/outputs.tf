output "gateway_public_url" {
  description = "Public URL for the Cloud Gateway"
  value       = "http://${aws_instance.cloud_gateway.public_ip}:8080"
}

output "eureka_public_url" {
  description = "Public URL for the Eureka Dashboard"
  value       = "http://${aws_instance.eureka_server.public_ip}:8761"
}

output "gateway_public_ip" {
  description = "Public IP of the Cloud Gateway"
  value       = aws_instance.cloud_gateway.public_ip
}

output "config_server_private_ip" {
  description = "Private IP of Config Server"
  value       = aws_instance.config_server.private_ip
}

output "eureka_server_private_ip" {
  description = "Private IP of Eureka Server"
  value       = aws_instance.eureka_server.private_ip
}

output "core_backend_private_ip" {
  description = "Private IP of Core Backend"
  value       = aws_instance.core_backend.private_ip
}

output "mtls_middleware_private_ip" {
  description = "Private IP of mTLS Middleware"
  value       = aws_instance.mtls_middleware.private_ip
}

output "user_bff_private_ip" {
  description = "Private IP of User BFF"
  value       = aws_instance.user_bff.private_ip
}

output "cloud_gateway_private_ip" {
  description = "Private IP of Cloud Gateway"
  value       = aws_instance.cloud_gateway.private_ip
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    config_server   = "ssh -i <key.pem> ubuntu@${aws_instance.config_server.public_ip}"
    eureka_server   = "ssh -i <key.pem> ubuntu@${aws_instance.eureka_server.public_ip}"
    core_backend    = "ssh -i <key.pem> ubuntu@${aws_instance.core_backend.public_ip}"
    mtls_middleware = "ssh -i <key.pem> ubuntu@${aws_instance.mtls_middleware.public_ip}"
    user_bff        = "ssh -i <key.pem> ubuntu@${aws_instance.user_bff.public_ip}"
    cloud_gateway   = "ssh -i <key.pem> ubuntu@${aws_instance.cloud_gateway.public_ip}"
  }
}

output "service_endpoints" {
  description = "Internal service endpoints"
  value = {
    config_server   = "http://${aws_instance.config_server.private_ip}:8888"
    eureka_server   = "http://${aws_instance.eureka_server.private_ip}:8761"
    core_backend    = "http://${aws_instance.core_backend.private_ip}:8082"
    mtls_middleware = "https://${aws_instance.mtls_middleware.private_ip}:8443"
    user_bff        = "http://${aws_instance.user_bff.private_ip}:8081"
    cloud_gateway   = "http://${aws_instance.cloud_gateway.private_ip}:8080"
  }
}
