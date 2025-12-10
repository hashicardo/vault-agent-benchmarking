data "cloudinit_config" "content" {
  gzip          = false
  base64_encode = false
  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/scripts/bootstrap.sh", {
      templates        = local.template_stanzas
      approle_roleid   = vault_approle_auth_backend_role.approle.role_id
      approle_secretid = vault_approle_auth_backend_role_secret_id.id.secret_id
      vault_addr       = var.vault_addr
      number_of_apps   = var.number_of_apps
      base_dir         = "/home/ubuntu"
    })
  }
}

resource "terraform_data" "provisioner" {
  triggers_replace = [
    data.cloudinit_config.content.rendered,
    aws_instance.benchmarkvm.id
  ]
  # Copy the script to the VM:
  provisioner "file" {
    source      = local_file.bootstrap.filename # Takes it from the generated file
    destination = "/home/ubuntu/bootstrap.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = aws_eip.ip.public_ip
    }
  }
  # Run the script:
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/bootstrap.sh",
      "sudo /home/ubuntu/bootstrap.sh",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = aws_eip.ip.public_ip
    }
  }
}