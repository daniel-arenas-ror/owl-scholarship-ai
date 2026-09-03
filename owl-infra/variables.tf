variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix for all resources"
  type        = string
  default     = "owl"
}

variable "instance_type" {
  description = "EC2 instance type (ARM64 / Graviton)"
  type        = string
  default     = "t4g.small"
}

variable "root_volume_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "domain" {
  description = "Apex domain, e.g. owl.example.com. Empty = skip Route 53."
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email for Let's Encrypt registration"
  type        = string
  default     = ""
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to reach port 22 (SSM is the primary access path; leave narrow)"
  type        = string
  default     = "127.0.0.1/32"
}

variable "ssm_prefix" {
  description = "SSM Parameter Store path prefix for runtime secrets"
  type        = string
  default     = "/owl"
}

variable "compose_version" {
  description = "docker compose plugin version installed on the host"
  type        = string
  default     = "2.29.7"
}
