# Vault Agent Benchmarking
This repo creates a few resources using Terraform and relies on the [`bootstrap.sh`](./scripts/bootstrap.sh) script to automate the lifecycle of a Vault agent, rotation of secrets and obtaining data to evaluate the performance of the agent.

The objective is to obtain two distinct benchmarks: 
1. How long does it take for the agent to initially render all templates for a given amount of secrets
2. How long does it take for the agent to change the template when a secret is rotated.

The [`bootstrap.sh`](./scripts/bootstrap.sh) script does this automatically by running a `remote-exec` provisioner. This is only done to see the output dynamically on the screen as soon as you run `terraform apply`.

## Try it out!
Copy the repo to run locally:
```bash
git clone && cd va-benchmark
```

Change to the directory, initialize and apply terraform:
```bash
terraform init
terraform apply #-auto-approve
```

### Troubleshooting rate limit errors
In my initial tests I got this error when executing the provisioner: `request path "sys/internal/ui/mounts/fi-secrets/secret-5": rate limit quota exceeded`.

After checking, I realized that the `sys/quotas/rate-limit/Global` was configured to only accept 60 secrets per second. If that's also your case we may need to raise the limit to perform this test. First create a JSON for the new values:

```bash
cat <<EOF > data.json
{
  "path": "admin/",
  "rate": 1000,
  "interval": 1
}
EOF
```

Update the rate limit of your Vault:

```bash
curl \
--request POST \
--header "X-Vault-Namespace: admin" \
--header "X-Vault-Token: $VAULT_TOKEN" \
--data @data.json \
$VAULT_ADDR/v1/sys/quotas/rate-limit/Global | jq
```

==============================
    INITIAL RENDER RESULTS
==============================
Initial template generation completed
Files: 200
Agent start ts: 1765359967671
Last file ts:   1765359970609
Total duration: 2938 ms
==============================
==============================
    SECRET ROTATION RESULTS
==============================
Samples: 200
Min: 161 ms
Max: 4812 ms
Avg: 2275.33 ms
==============================

The authentication of the agent is created by terraform with approle. Check all the configs in [`vault.tf`](./vault.tf)