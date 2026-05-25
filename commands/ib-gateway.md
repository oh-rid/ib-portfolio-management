---
description: "Manage IB Client Portal Gateway (start/stop/status/setup/update)"
argument-hint: "<start|stop|status|setup|update> [TIMEOUT_MINUTES]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/gateway.sh:*)", "Bash(curl:*)"]
---

# IB Gateway

Manage the IB Client Portal Gateway.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/gateway.sh" "${CLAUDE_PLUGIN_ROOT}" $ARGUMENTS
```

After `start`: user must open the URL shown, log in, and say "ready". Then verify:

```bash
curl -sk https://localhost:$(grep 'listenPort:' "${CLAUDE_PLUGIN_ROOT}/gateway/root/conf.yaml" | awk '{print $2}')/v1/api/tickle
```

If `authenticated: true` — session is live. If not — ask user to log in again.
