# These are just for debugging and checking the generated files

resource "local_file" "agent_config" {
  content = templatefile(
    "${path.module}/templates/agent_config.hcl.tftpl",
  { vault_addr = var.vault_addr, templates = local.template_stanzas })
  filename = "${path.module}/generated/agent_config.hcl"
}

resource "local_file" "bootstrap" {
  content = templatefile("${path.module}/scripts/bootstrap.sh", {
    templates        = local.template_stanzas
    approle_roleid   = vault_approle_auth_backend_role.approle.role_id
    approle_secretid = vault_approle_auth_backend_role_secret_id.id.secret_id
    vault_addr       = var.vault_addr
    number_of_apps   = var.number_of_apps
    base_dir         = "/home/ubuntu"
  })
  filename = "${path.module}/generated/bootstrap.sh"
}