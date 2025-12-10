terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.6.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.25.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
  }
}

provider "vault" {
  # Configured via env vars: VAULT_ADDR, VAULT_TOKEN and VAULT_NAMESPACE
}

provider "aws" {
  region = var.aws_region
}