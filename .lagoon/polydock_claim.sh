#!/bin/sh

# Build the same OpenClaw dashboard URL as .lagoon/50-shell-config.sh
# and print only the URL (required by Polydock claim command parsing).
#
# Why we refresh config here:
# - Claim may be executed with environment variables injected at runtime
#   (for example via kubectl exec / Polydock labels).
# - Those variables are only present in this claim process and are NOT injected
#   into the already-running OpenClaw gateway process environment.
# - 60-amazeeai-config.sh reads the current env and writes resolved values into
#   /home/.openclaw/openclaw.json.
# - Running it here materializes the latest claim-time values (like
#   AMAZEEAI_API_KEY / AMAZEEAI_DEFAULT_MODEL) without restarting the container.
# - Keep this script output to URL-only so Polydock claim parsing remains stable.

# Refresh OpenClaw config so claim-time environment labels (for example
# AMAZEEAI_* variables) are materialized into openclaw.json before URL output.
__oc_refresh_config() {
  if [ -r /lagoon/entrypoints/60-amazeeai-config.sh ]; then
    /bin/sh /lagoon/entrypoints/60-amazeeai-config.sh >/dev/null 2>&1 || true
  fi
}

__oc_refresh_config

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
