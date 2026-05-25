#!/bin/bash
set -euo pipefail

# Block IB order-placement endpoints in any curl/fetch command.
# This is a safety net — the ib-connector skill already says NO ORDERS,
# but this hook enforces it at the tool level.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# No command — not a Bash call we care about
if [ -z "$command" ]; then
  exit 0
fi

# Patterns that indicate order placement via CP Gateway
# POST /iserver/account/{id}/order  — place order
# POST /iserver/account/{id}/orders — place multiple orders
# DELETE /iserver/account/{id}/order/{orderId} — cancel order
# POST /iserver/reply/{replyid} — confirm order execution
if echo "$command" | grep -qiE '/iserver/account/[^/]+/orders?\b|/iserver/reply/'; then
  echo '{"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage":"BLOCKED: IB order endpoint detected. This plugin is read-only. Orders must be placed through TWS Desktop or IB mobile app."}' >&2
  exit 2
fi

exit 0
