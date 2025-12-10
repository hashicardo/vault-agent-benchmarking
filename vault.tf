# Mount for static secrets
resource "vault_mount" "kvv2" {
  path        = "fi-secrets"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine mount"
}

locals {
  secret = "superSecret" #change this to trigger new secret versions
}

# 200 kv secrets
resource "vault_kv_secret_v2" "creds" {
  count = var.number_of_apps
  mount = vault_mount.kvv2.path
  name  = "secret-${count.index}"
  data_json = jsonencode(
    {
      "username" = "fi-user-${count.index}"
      "password" = "${local.secret}-${count.index}"
    }
  )
}

# Policy for the agent
resource "vault_policy" "agent-policy" {
  name = "agent-read-fi"
  policy = templatefile("${path.module}/templates/agent_policy.hcl.tftpl", {
    secrets_path = "${vault_mount.kvv2.path}"
  })
}

# Auth for the agent - approle:
resource "vault_auth_backend" "approle" {
  type = "approle"
}

resource "vault_approle_auth_backend_role" "approle" {
  backend        = vault_auth_backend.approle.path
  role_name      = "fi-agent-role"
  token_policies = [vault_policy.agent-policy.name]
  token_ttl      = 3600 * 24
  token_max_ttl  = 86400 * 7
}

resource "vault_approle_auth_backend_role_secret_id" "id" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.approle.role_name
}

# Some things needed for the agent:
locals {
  # Template stanzas for Vault Agent configuration:
  template_stanzas = [for idx in range(var.number_of_apps) :
    {
      idx         = idx
      source      = "va_templates/app-${idx}-template.ctmpl"
      destination = "config_files/app-${idx}.conf"
    }
  ]
}