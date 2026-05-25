---
name: finance
description: Launch the finance agent for market analysis, macro, options, news, portfolio review.
parse_arguments: passthrough
---

Spawn the `portfolio-agent` agent from the `ib-portfolio-management` plugin using the Agent tool. Pass the user's full message as the agent's prompt. If no message was provided, ask the user what they want to analyze.
