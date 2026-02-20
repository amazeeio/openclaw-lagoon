#!/bin/sh

# Build the same OpenClaw dashboard URL as .lagoon/50-shell-config.sh
# and print only the URL (required by Polydock claim command parsing).

# Helper to get gateway token (from env var or config file)
__oc_get_token() {
  # First check environment variable
  if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    echo "$OPENCLAW_GATEWAY_TOKEN"
    return
  fi

  # Fall back to reading from config file
  config_dir="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
  config_file="$config_dir/openclaw.json"

  if [ -f "$config_file" ]; then
    node -e "
      try {
        const c = require('$config_file');
        if (c.gateway?.auth?.token) console.log(c.gateway.auth.token);
      } catch {}
    " 2>/dev/null
  fi
}

# Determine base dashboard URL (LAGOON_ROUTE or localhost fallback)
__oc_base_url="${LAGOON_ROUTE:-http://localhost:${OPENCLAW_GATEWAY_PORT:-3000}}"
__oc_token="$(__oc_get_token)"

# Build full dashboard URL with token
if [ -n "$__oc_token" ]; then
  echo "${__oc_base_url}?token=${__oc_token}"
else
  echo "$__oc_base_url"
fi
