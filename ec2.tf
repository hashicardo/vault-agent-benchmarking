# This is for creating a publicly accessible EC2 where the remote-exec provisioner will run to benchmark the Vault Agent behavior

# NETWORKING:
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name           = "demo-va-benchmark"
  cidr           = "10.0.0.0/16"
  public_subnets = ["10.0.101.0/24"]
  azs            = ["${var.aws_region}a"]
  tags = {
    Terraform   = "true"
    Environment = "demo"
  }
}

# Security group
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic and all outbound traffic"
  vpc_id      = module.vpc.default_vpc_id

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = "${var.source_public_ip}/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Public IP:
resource "aws_eip" "ip" {
  instance = aws_instance.benchmarkvm.id
  domain   = "vpc"
}

# COMPUTE

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "benchmarkvm" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.allow_ssh.name]
  key_name        = aws_key_pair.vm_key.key_name
  #   user_data_base64            = base64gzip(data.cloudinit_config.content.rendered) # using provisioner instead
  #   user_data_replace_on_change = true

  tags = {
    Name = "va-benchmark"
  }
}

resource "aws_key_pair" "vm_key" {
  key_name   = "vab-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}