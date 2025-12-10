# NOTE: This is embedded in the bootstrap.sh script. Is here just for reference.

#!/bin/bash
set -euo pipefail

# --- Input ---
# $1 = template index (e.g., 0, 1, 2, ...)
idx="$1"
t0=$(cat "/tmp/t0/${idx}")
now=$(date +%s%3N)
delta=$((now - t0))
# Store idx, t0_ms, now_ms, delta_ms
printf "%s,%s,%s,%s\n" "$idx" "$t0" "$now" "$delta" >> /tmp/vault-agent-benchmark.csv