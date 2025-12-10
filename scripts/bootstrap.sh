#!/bin/bash
set -eou pipefail

# NOTE: this is intended to run in Ubuntu / Debian.

LOGFILE="/var/log/cloud-init-agent.log"

function log {
  local level="$1"
  local message="$2"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local log_entry="$timestamp [$level] - $message"

  echo "$log_entry" | sudo tee -a "$LOGFILE"
}

# This runs when ANY command fails
function on_error {
  local exit_code=$?
  local line_no=$1
  log "ERROR" "Script failed with exit code $exit_code at line $line_no"
}

trap 'on_error $LINENO' ERR

BASE_DIR="/home/ubuntu"

log "INFO" "Beginning bootstrap script."

if ! command -v vault >/dev/null 2>&1; then
  log "INFO" "Installing required packages - Vault"
  wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update
  sudo apt install -y vault
fi

log "INFO" "Starting creation of files"
log "INFO" "Creating $BASE_DIR/vault-agent-benchmark.csv file"
# Create the benchmark CSV file with header
echo "template_idx,t0_ms,now_ms,delta_ms" | sudo tee $BASE_DIR/vault-agent-benchmark.csv

# NOTE: I include the store_info script here because it will be used by the VA:
log "INFO" "Creating store_info.sh script"
sudo tee /usr/local/bin/store_info.sh > /dev/null << 'EOF'
#!/bin/bash
set -euo pipefail

# --- Input ---
# $1 = template index (e.g., 0, 1, 2, ...)
idx="$1"
t0_file="${base_dir}/t0/$${idx}"

# If the t0 file does not exist yet, skip logging gracefully
if [[ ! -f "$t0_file" ]]; then
  # Optional: track skipped entries somewhere
  echo "t0 file not found for idx=$${idx}, skipping." >> "${base_dir}/vault-agent-benchmark-skipped.log"
  exit 0
fi

t0=$(cat "$t0_file")
now=$(date +%s%3N)
delta=$((now - t0))
# Store idx, t0_ms, now_ms, delta_ms
printf "%s,%s,%s,%s\n" "$idx" "$t0" "$now" "$delta" >> "${base_dir}/vault-agent-benchmark.csv"
EOF

# Make the script executable
sudo chmod +x /usr/local/bin/store_info.sh

# Create the dir for the templates
sudo mkdir -p $BASE_DIR/va_templates

log "INFO" "Creating templates for Vault Agent (one for each secret)"
%{ for t in templates ~}
sudo tee $BASE_DIR/${t.source} > /dev/null << 'EOF'
# Dummy of an application configuration file
app:
name: example-application
environment: production

database:
host: db.internal.example.com
port: 5432
name: appdb

#################################
#   Vault-rendered credentials  #
#################################
username: {{ with secret "fi-secrets/data/secret-${t.idx}" }}{{ .Data.data.username }}{{ end }}
password: {{ with secret "fi-secrets/data/secret-${t.idx}" }}{{ .Data.data.password }}{{ end }}
EOF

%{ endfor ~}

# For the rendered configs:
sudo mkdir -p $BASE_DIR/config_files

log "INFO" "Creating approle files"
sudo mkdir -p $BASE_DIR/approle
echo "${approle_roleid}" | sudo tee $BASE_DIR/approle/roleid > /dev/null
echo "${approle_secretid}" | sudo tee $BASE_DIR/approle/secretid > /dev/null

# For t0 timestamps
sudo mkdir -p $BASE_DIR/t0

# Create Vault Agent configuration
sudo mkdir -p /etc/vault

log "INFO" "Creating Vault Agent configuration file"
sudo tee /etc/vault/agent-config.hcl > /dev/null << EOF
pid_file = "$BASE_DIR/va_pidfile"
log_file = "/var/log/vault-agent.log"

vault {
  address = "${vault_addr}"
  namespace = "admin"
  retry {
    num_retries = 5
  }
}

auto_auth {
  method {
    type = "approle"
    config = {
      role_id_file_path = "$BASE_DIR/approle/roleid"
      secret_id_file_path = "$BASE_DIR/approle/secretid"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "$BASE_DIR/approle/sink"
    }
  }
}

template_config {
  static_secret_render_interval = "5s"
  exit_on_retry_failure = true
  max_connections_per_host = 20
}

%{ for t in templates ~}
template {
  source      = "$BASE_DIR/${t.source}"
  destination = "$BASE_DIR/${t.destination}"
  command     = "/usr/local/bin/store_info.sh ${t.idx}"
}
%{ endfor ~}
EOF


# The following is for measuring the time taken to create all configs for the first time
# Flow: 1. Capture timestamp 2. Start agent, 3. Poll creation of config files
# 1. Record agent start time
date +%s%3N > $BASE_DIR/agent_start_ts
agent_start_ts=$(cat $BASE_DIR/agent_start_ts)

# 2. Start Vault Agent
# First gracefully stop any previous instance:
VAULT_PID_FILE="$BASE_DIR/va_pidfile"

if [[ -f "$VAULT_PID_FILE" ]]; then
  vault_pid=$(sudo cat "$VAULT_PID_FILE")

  if [[ -n "$vault_pid" ]] && ps -p "$vault_pid" > /dev/null 2>&1; then
    log "INFO" "Stopping Vault Agent using PID $vault_pid"
    
    sudo kill "$vault_pid"

    # Optional: wait up to 5 seconds for clean shutdown
    for i in {1..5}; do
      if ! ps -p "$vault_pid" > /dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    # If it’s still alive, force kill
    if ps -p "$vault_pid" > /dev/null 2>&1; then
      log "WARN" "Vault Agent did not exit gracefully, force killing"
      sudo kill -9 "$vault_pid"
    fi

  else
    log "INFO" "Vault Agent PID file exists but process is not running"
  fi

  # Always remove stale PID file
  sudo rm -f "$VAULT_PID_FILE"
else
  log "INFO" "No Vault Agent PID file found — nothing to stop"
fi

# Now start:
log "INFO" "Starting Vault Agent at $${agent_start_ts} ms"
sudo vault agent -config=/etc/vault/agent-config.hcl &
AGENT_PID=$!

# 3. Poll until all config files exist
CONFIG_DIR="$BASE_DIR/config_files" # nothing else but config files should be here
EXPECTED=${number_of_apps}
RESULTS="$BASE_DIR/results.log"

log "INFO" "Polling for $EXPECTED rendered config files..."

start_poll_ts=$(date +%s%3N)

while true; do
  count=$(ls -1 "$CONFIG_DIR" 2>/dev/null | wc -l)

  if [[ "$count" -ge "$EXPECTED" ]]; then
    last_ts=$(date +%s%3N)
    total_ms=$((last_ts - agent_start_ts))

    cat << EOF | sudo tee "$RESULTS" > /dev/null
==============================
    INITIAL RENDER RESULTS
==============================
Initial template generation completed
Files: $EXPECTED
Agent start ts: $agent_start_ts
Last file ts:   $last_ts
Total duration: $${total_ms} ms
==============================

EOF

    log "INFO" "Initial render benchmark completed in $${total_ms} ms"
    break
  fi

  sleep 0.01   # 10ms polling resolution
# NOTE: this will have a 10ms granularity. If the creation of config files is faster than this it will impact accuracy.
done

log "INFO" "All $EXPECTED rendered config files created."
log "INFO" "Initializing secret rotation monitoring."

export VAULT_ADDR=${vault_addr}
export VAULT_NAMESPACE="admin"
export VAULT_TOKEN=$(sudo cat $BASE_DIR/approle/sink) # this approle had the permissions to also write the secrets

t0_dir="$BASE_DIR/t0"
LOG="$BASE_DIR/rotation-events.log"
rm -f "$LOG" # Delete previous log if any

for i in $(seq 0 $((${number_of_apps} - 1))); do
  # Adding a timestamp: remember that the "command" in the template will execute ONLY when the resulting file has changed. That's why I'm adding the timestamp
  vault kv put fi-secrets/secret-$${i} username="rotatedUser$${i}_$(date +%s)" password="rotatedPass$${i}_$(date +%s)"
  echo "$(date +%s%3N)" | sudo tee "$t0_dir/$${i}" > /dev/null
  # From this moment on, the store_info script will log each rotation event and time.
  echo "Rotated secret fi-secrets/secret-$${i}" >> "$LOG"
done

sleep 5 # Wait for a few seconds to finish the last template to be rendered
log "INFO" "Running basic analytics on rotation events"
# To add a little header to the results file
cat << EOF | sudo tee -a "$RESULTS" > /dev/null

==============================
    SECRET ROTATION RESULTS
==============================
EOF

awk -F',' '
NR==1 { next }  # skip header
{
  d = $4
  sum += d
  count++
  if (count == 1 || d < min) min = d
  if (count == 1 || d > max) max = d
}
END {
  printf "Samples: %d\nMin: %d ms\nMax: %d ms\nAvg: %.2f ms\n", count, min, max, sum/count
}
' vault-agent-benchmark.csv | sudo tee -a "$RESULTS" > /dev/null

cat << EOF | sudo tee -a "$RESULTS" > /dev/null
==============================
EOF

cat "$RESULTS"

log "INFO" "Bootstrap script completed successfully"
log "INFO" "SSH to check results by running: 'terraform output -raw ssh_key > key.pem && chmod 600 key.pem && ssh -i key.pem ubuntu@$(terraform output -raw vm_public_ip)'"
log "INFO" "Find results and logs by running 'cat $BASE_DIR/results.log' and 'cat $BASE_DIR/vault-agent-benchmark.csv'"