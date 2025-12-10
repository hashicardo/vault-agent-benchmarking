# Vault Agent Benchmarking
This repo creates a few resources using Terraform and relies on the [`bootstrap.sh`](./scripts/bootstrap.sh) script to automate the lifecycle of a Vault agent, rotation of secrets and obtaining data to evaluate the performance of the agent.

The objective is to obtain two distinct benchmarks: 
1. How long does it take for the agent to initially render all templates for a given amount of secrets
2. How long does it take for the agent to change the template when a secret is rotated.

The [`bootstrap.sh`](./scripts/bootstrap.sh) script does this automatically by running a `remote-exec` provisioner. This is only done to see the output dynamically on the screen as soon as you run `terraform apply`.

Scroll to 'How it works' for an explanation.

## Try it out!
Copy the repo to run locally:
```bash
git clone https://github.com/hashicardo/vault-agent-benchmarking.git && cd vault-agent-benchmarking
```

### Add your variables in [`variables.tf`](./variables.tf):
- Specify a number of secrets by modifying the `number_of_apps` variable. This will create that many secrets in Vault (inside a path called `fi-secrets`). 
>NOTE: You may change this path in [`vault.tf`](./vault.tf) but be advised this may break the whole bootstrap script. A future version of this repo should allow for a path passed as a tf variable instead.

The boostrap.sh script will also automate the creation of that many templates and the Vault Agent config for all of them.

- Add your IP address in the `source_public_ip` variable. This is passed to the security group in AWS to allow inbound SSH connections. This is required for the `remote-exec` provisioner.

- Add your Vault add in `vault_addr` (this is passed to the script). And also export env variables for terraform to run:
```bash
export VAULT_ADDR=<your addr>
export VAULT_TOKEN=<your admin token>
export VAULT_NAMESPACE=admin
```

- Export your credentials for AWS to the current terminal session.

### Apply and run

Initialize and apply terraform:
```bash
terraform init
terraform apply #-auto-approve
```

After applying you should see multiple resources being created by terraform: a `number_of_apps` amount of secrets in Vault, an EC2 instance in AWS where all this logic will run, some extra things and the `remote_exec` provisioner.

## Initial results:
I ran this test with 200, 500 and 1000 secrets and got the following results:
### 200 secrets (and templates and config files)
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
```

### 500 secrets
```
==============================
    INITIAL RENDER RESULTS
==============================
Initial template generation completed
Files: 500
Agent start ts: 1765365670283
Last file ts:   1765365675108
Total duration: 4825 ms
==============================


==============================
    SECRET ROTATION RESULTS
==============================
Samples: 500
Min: 224 ms
Max: 5005 ms
Avg: 2609.07 ms
==============================
```
### 1000 secrets
```
==============================
    INITIAL RENDER RESULTS
==============================
Initial template generation completed
Files: 1000
Agent start ts: 1765367135489
Last file ts:   1765367143630
Total duration: 8141 ms
==============================


==============================
    SECRET ROTATION RESULTS
==============================
Samples: 1000
Min: 427 ms
Max: 5392 ms
Avg: 2777.44 ms
==============================
```

## Troubleshooting 

### Provisioner timeout error
This may happen if your IP address is not passed to the security group. Make sure to retrieve it from https://icanhazip.com and add it to the [`variables.tf`](./variables.tf) file.

### Rate limit errors
In my initial tests I got this error when executing the provisioner: `request path "sys/internal/ui/mounts/fi-secrets/secret-5": rate limit quota exceeded`.

After checking, I realized that the `sys/quotas/rate-limit/Global` was configured to only accept 60 requests per second. If that's also your case we may need to raise the limit to perform this test. This is how you can do that:

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

>NOTE: this should only be done to perform this test. There's a reason for the limit to be there, make sure to put a limit that meets your needs but keeps everything safe.

## How this works
- Terraform creates the EC2, secrets and triggers the execution of the bootstrap script with a provisioner.
- The authentication of the agent is also created by terraform with approle. Check all the configs in [`vault.tf`](./vault.tf)
- Additionally, terraform also creates the agent config and the rendered bootstrap script inside a directory called `generated/`. This is mostly just for visualization but the provisioner does take the rendered bootstrap.sh to copy it to the target machine and execute it from there.

### The bootstrap script
The idea of the script is to configure and start the agent and rotate secrets. Simultaneously it generates the two benchmarks explained above like this:

1. Time to initially render all templates for a given amount of secrets
    
The script starts the agent and generates a timestamp in milliseconds and at the same time it starts a 'watcher' in the destination of all the rendered config files (`/home/ubuntu/config_files`). 

When all the 'expected' templates (i.e. the specified number in the variables) are rendered, another timestamp is taken and the result it's compared to the initial timestamp. 
>NOTE: this 'watcher' in reality is a polling mechanism with a resolution of 10ms. From the initial tests I saw that the actual time to render templates was over 1000ms (for more than 50 secrets/apps) which gives us a safe margin of a few orders of magnitude higher than the sampling period.

2. Time to change the template when a secret is rotated.

After all the initial templates have been rendered, the script makes a quick pause and starts rotating all the secrets. This is done because of the wide difference I found when changing one secret or another. Instead of just measuring the time of one template being updated I'm updating all secrets and taking the average, makes it a bit more accurate.

The way this works is by leveraging the [`command`](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent/template#command) configuration from the Vault Agent template stanza. A timestamp in ms is generated when the secret is rotated and then another timestamp is created with this `command` option. The reason to use this is that this command is only executed when the template actually changes, which gives us a cool little native mechanism to figure out when the template has indeed been updated.

All these timestamps and their deltas are stored inside `/home/ubuntu/vault-agent-benchmark.csv`.  After this file is generated we take the shortest time, longest time and average. 

The results of the tests for both benchmarks are then presented in `/home/ubuntu/results.log`