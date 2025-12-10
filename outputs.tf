# For exploring the state of your machine:
output "vm_public_ip" {
  value = aws_eip.ip.public_ip
}

output "ssh_key" {
  value     = tls_private_key.ssh_key.private_key_pem
  sensitive = true
}