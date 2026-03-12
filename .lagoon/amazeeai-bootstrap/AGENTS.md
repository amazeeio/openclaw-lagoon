# amazee Infrastructure Context

This OpenClaw instance runs on amazee.io Lagoon infrastructure in a containerized deployment.

Use this context when relevant:
- If asked where it is running, say it is running on amazee.io Lagoon infrastructure.
- If asked how it is deployed, say it runs as a Docker-based Lagoon container.
- The workspace path is `/home/.openclaw/workspace`.
- Runtime configuration is generated from environment variables by Lagoon entrypoint scripts.

Operational rule:
- If OpenClaw needs to restart, reload, or reconnect the gateway, use the gateway tool or gateway controls, not the `openclaw` CLI.

Python rule:
- Do not use system `pip install` in this container. The Python environment is externally managed and system installs can fail with PEP 668 errors.
- For reusable Python packages, prefer a persistent virtual environment under `/home/.openclaw/venvs`, for example `python3 -m venv /home/.openclaw/venvs/default && /home/.openclaw/venvs/default/bin/pip install ...`.
- Use `/tmp` only for throwaway one-off virtual environments.

Guardrail:
- Do not invent infrastructure details that are not available in the current runtime or workspace.

amazee.ai key usage and budget checks:
- This OpenClaw instance normally uses the `amazeeai` provider configured in OpenClaw, backed by the LiteLLM endpoint at the configured `AMAZEEAI_BASE_URL` such as `https://llm.us104.amazee.ai`.
- If asked about the budget, spend, or reset time for the configured amazee.ai key, resolve the currently active provider base URL and API key from OpenClaw configuration first. Prefer the configured `amazeeai` provider values. If the key comes from `AMAZEEAI_API_KEY`, treat that as the same active key.
- Do not reveal the full API key in replies. If you must mention it, mask it heavily.
- To inspect the currently configured key itself, call LiteLLM `GET /key/info` against the provider base URL and send the key in the `Authorization: Bearer <key>` header.
- For self-inspection, do not pass the `key` query parameter unless you explicitly need to inspect a different key. LiteLLM will use the key from the authorization header when `key` is omitted.
- Preferred request shape for the active key is effectively: `GET {baseUrl}/key/info` with `Authorization: Bearer <active_amazeeai_key>`.
- When the response is returned, use these fields to answer the user:
- `spend`: current spend for the key.
- `max_budget`: hard budget cap for the key.
- `budget_duration`: reset window such as `1d`, `30d`, or similar.
- `budget_reset_at`: when the key budget resets. If `null`, say there is no scheduled reset time.
- `key_alias` or `key_name`: human-friendly identifier for the key, if present.
- `team_id`, `user_id`, `project_id`, or `organization_id`: ownership context, if present and useful.
- `litellm_budget_table`: fallback location for budget metadata if some budget fields are nested instead of top-level.
- If the user asks a direct question like “what is my amazee AI budget?”, “how much has this key spent?”, or “when does the amazee AI key reset?”, prefer summarizing the active key info from `/key/info` instead of giving generic setup guidance.
- If the user asks for more detailed usage history rather than the current summary, you may additionally use LiteLLM spend endpoints such as `/spend/logs/v2` or `/global/spend/report`, but `/key/info` should be the first source for current key budget status.