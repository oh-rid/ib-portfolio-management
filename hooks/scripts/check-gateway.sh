#!/bin/bash
set -uo pipefail

# SessionStart hook — report whether the IB CP Gateway is up + authenticated.
# Read by Claude so it knows whether live data is available.

# Resolve port from conf.yaml if the plugin is installed at the standard
# location; otherwise fall back to 5000 (IB out-of-box default).
PORT=5000
CONF="${CLAUDE_PLUGIN_ROOT:-}/gateway/root/conf.yaml"
if [[ -f "$CONF" ]]; then
  P=$(grep 'listenPort:' "$CONF" 2>/dev/null | awk '{print $2}')
  [[ -n "$P" ]] && PORT="$P"
fi

GATEWAY_URL="https://localhost:${PORT}/v1/api/tickle"

if ! pgrep -f "clientportal.gw" > /dev/null 2>&1; then
  echo "{\"systemMessage\":\"IB CP Gateway is NOT running. Run /ib-gateway start to launch.\"}"
  exit 0
fi

response=$(curl -sk --connect-timeout 3 --max-time 5 "$GATEWAY_URL" 2>/dev/null) || {
  echo "{\"systemMessage\":\"IB CP Gateway process found but not responding on port ${PORT}. Try /ib-gateway stop then /ib-gateway start.\"}"
  exit 0
}

authenticated=$(echo "$response" | jq -r '.iserver.authStatus.authenticated // false' 2>/dev/null)

if [ "$authenticated" = "true" ]; then
  echo "{\"systemMessage\":\"IB CP Gateway is running and authenticated on port ${PORT}. Live market data available.\"}"
else
  echo "{\"systemMessage\":\"IB CP Gateway is running on port ${PORT} but NOT authenticated. Open https://localhost:${PORT} in browser to log in.\"}"
fi

exit 0
