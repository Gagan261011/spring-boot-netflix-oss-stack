variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "admin_cidr" {
  description = "CIDR block for SSH access (your IP)"
  type        = string
  default     = "0.0.0.0/0"  # Change this to your IP for security
}

variable "git_repo_url" {
  description = "Git repository URL to clone"
  type        = string
  default     = "https://github.com/your-org/spring-boot-netflix-oss-stack.git"
}

variable "git_branch" {
  description = "Git branch to checkout"
  type        = string
  default     = "main"
}

variable "key_pair_name" {
  description = "AWS Key Pair name for SSH access"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "netflix-oss-stack"
}
