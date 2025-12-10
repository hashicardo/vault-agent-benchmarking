variable "number_of_apps" {
  type        = number
  description = "This represents the number of apps that require a config file."
  default     = 200
}

variable "instance_type" {
  type        = string
  default     = "t4g.medium"
  description = "Type of the EC2 instance. Different sizes should give different results."
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy the EC2 instance in."
}

variable "vault_addr" {
  type    = string
  default = "https://r2-vault-public-vault-36f2a406.563cbed7.z1.hashicorp.cloud:8200"
}

variable "source_public_ip" {
  type        = string
  default     = "46.26.36.56"
  description = "Your public IP. You can get it by running 'curl ifconfig.me' OR 'curl icanhazip.com' from your terminal OR visiting https://icanhazip.com/"
}