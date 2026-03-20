# OpenClaw for Lagoon

This repository provides the Lagoon-facing deployment for OpenClaw. It uses the published OpenClaw Lagoon base image so projects can deploy OpenClaw with minimal per-project configuration while reusing a shared runtime image from GHCR.

The reusable runtime image is maintained in the `openclaw-lagoon-base` repository and published as `ghcr.io/amazeeio/openclaw-lagoon-base:latest`.

## What this repository does

- Pulls the published base image in Lagoon and local Docker Compose
- Supplies deployment-specific environment variables and persistent volume mounts
- Keeps the Lagoon-facing service definition stable for downstream consumers

## Relationship to the base repo

`openclaw-lagoon-base` owns the shared runtime image used by this repository. That includes:

- OpenClaw installation and OS packages
- Lagoon entrypoint orchestration
- SSH key bootstrap for Git operations
- amazee.ai model discovery and runtime config generation
- Shell prompt and dashboard URL helpers
- Bundled bootstrap files copied into the runtime workspace

If you need to change the runtime image itself, make that change in `openclaw-lagoon-base`, publish a new image, and then update this repository if needed.

## Prerequisites

- A Lagoon account with access to create repositories
- Access to an LLM API provider such as amazee.ai
- Access to the published image `ghcr.io/amazeeio/openclaw-lagoon-base:latest`

## Lagoon deployment

### 1. Add the repository to Lagoon

Add this repository as a Lagoon project. Lagoon will pull the published base image defined in `docker-compose.yml`.

### 2. Configure environment variables

Before deploying, configure these variables in your Lagoon project:

| Variable | Description | Example |
|----------|-------------|---------|
| `AMAZEEAI_BASE_URL` | Base URL for your LLM API provider | `https://llm.us104.amazee.ai` |
| `AMAZEEAI_API_KEY` | API key for authentication | `your-api-key-here` |
| `AMAZEEAI_DEFAULT_MODEL` | Default model to use | `claude-4-5-sonnet` |

You can set these values through the Lagoon UI or CLI before deployment.

Optional integrations still work through environment variables:

| Variable | Description |
|----------|-------------|
| `SLACK_APP_TOKEN` | Slack Socket Mode app token |
| `SLACK_BOT_TOKEN` | Slack bot token |
| `SSH_PRIVATE_KEY` | OpenSSH private key for Git access |

### 3. Deploy

Deploy the project. Lagoon will pull the published image and start the OpenClaw gateway.

### 4. Connect and approve pairing

After deployment, connect over SSH:

```bash
lagoon ssh -p [projectname] -e [environmentname] -s openclaw-gateway
```

Once connected, OpenClaw will show the dashboard URL with its token. Open that URL in your browser, then approve the pending device pairing:

```bash
openclaw devices list
openclaw devices approve <request_id>
```

After approval, return to the dashboard and start the initial conversation there.

## amazee.ai model discovery

When `AMAZEEAI_BASE_URL` and `AMAZEEAI_API_KEY` are configured, the runtime performs model discovery during startup. That lets OpenClaw populate its available models automatically instead of requiring a hand-maintained model list in this repository.

At startup the image will:

- Query the amazee.ai `/v1/models` endpoint with your credentials
- Discover the models available to that API key
- Inject those models into OpenClaw's runtime configuration
- Apply `AMAZEEAI_DEFAULT_MODEL` as the default when it is available

This keeps the model list aligned with the account behind the API key. If model access changes, restart or redeploy the service to refresh discovery.

Typical startup logs look like this:

```text
[amazeeai-config] Discovering models from: https://llm.us104.amazee.ai
[amazeeai-config] Discovered 5 models:
[amazeeai-config]   - claude-4-5-sonnet
[amazeeai-config]   - claude-4-opus
[amazeeai-config]   - gpt-4o
[amazeeai-config]   - gpt-4o-mini
[amazeeai-config]   - o1
[amazeeai-config] Set default model to: amazeeai/claude-4-5-sonnet
```

## Slack integration

Slack support is optional, but the shared runtime image still supports it. For the full product-level behavior, refer to the official OpenClaw Slack documentation: https://docs.openclaw.ai/channels/slack

### 1. Create a Slack app

Create a Slack app from a manifest. Before importing it, replace the placeholder values for the bot name, description, and assistant description.

```json
{
	"display_information": {
		"name": "YOUR_BOT_NAME",
		"description": "YOUR_BOT_DESCRIPTION"
	},
	"features": {
		"app_home": {
			"home_tab_enabled": false,
			"messages_tab_enabled": true,
			"messages_tab_read_only_enabled": false
		},
		"bot_user": {
			"display_name": "YOUR_BOT_NAME",
			"always_online": true
		},
		"assistant_view": {
			"assistant_description": "Describe what your bot can do here",
			"suggested_prompts": []
		}
	},
	"oauth_config": {
		"scopes": {
			"bot": [
				"chat:write",
				"channels:history",
				"channels:read",
				"groups:history",
				"groups:read",
				"groups:write",
				"im:history",
				"im:read",
				"im:write",
				"mpim:history",
				"mpim:read",
				"mpim:write",
				"users:read",
				"app_mentions:read",
				"reactions:read",
				"reactions:write",
				"pins:read",
				"pins:write",
				"emoji:read",
				"commands",
				"files:read",
				"files:write",
				"assistant:write"
			]
		}
	},
	"settings": {
		"event_subscriptions": {
			"bot_events": [
				"app_mention",
				"assistant_thread_started",
				"channel_rename",
				"member_joined_channel",
				"member_left_channel",
				"message.channels",
				"message.groups",
				"message.im",
				"message.mpim",
				"pin_added",
				"pin_removed",
				"reaction_added",
				"reaction_removed"
			]
		},
		"interactivity": {
			"is_enabled": true
		},
		"org_deploy_enabled": false,
		"socket_mode_enabled": true,
		"token_rotation_enabled": false
	}
}
```

### 2. Generate Slack tokens

After creating the app:

- Generate an app-level token that starts with `xapp-`
- Install the app to your workspace to get the bot user OAuth token that starts with `xoxb-`

### 3. Add the Slack variables in Lagoon

Set these environment variables on the Lagoon project:

| Variable | Description | Example |
|----------|-------------|---------|
| `SLACK_APP_TOKEN` | App-level token for Socket Mode | `xapp-1-A123...` |
| `SLACK_BOT_TOKEN` | Bot user OAuth token | `xoxb-123...` |

### 4. Redeploy and approve pairing

Redeploy the project after adding the tokens. OpenClaw will detect the Slack configuration at startup. The first time you interact with the bot, you still need to approve the device pairing from the Lagoon SSH session just as you do for the web UI.

### 5. Test direct messages and channels

After deployment, send the bot a direct message. If you want it to work in channels, add it to the channel and enable that channel through a direct message workflow in OpenClaw. The official Slack documentation covers the channel-specific behavior in more detail.

## Git repository access

If OpenClaw needs to clone or push to Git repositories, provide a dedicated SSH private key through `SSH_PRIVATE_KEY`.

### 1. Create a dedicated key pair

Do not reuse a personal SSH key. Create a dedicated key with access limited to only the repositories the bot needs.

```bash
ssh-keygen -t ed25519 -C "openclaw-bot@your-domain.com" -f ~/.ssh/openclaw_bot
```

Add the public key to your Git provider as a deploy key or bot-specific SSH key.

### 2. Format the private key for Lagoon

Lagoon environment variables must store the private key as a single line with escaped newlines:

```bash
awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ~/.ssh/openclaw_bot
```

The output should look like this:

```text
-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA...\n-----END OPENSSH PRIVATE KEY-----\n
```

### 3. Set the environment variable

Add the formatted value to Lagoon:

| Variable | Description | Format |
|----------|-------------|--------|
| `SSH_PRIVATE_KEY` | OpenSSH private key for Git operations | Single-line string with `\n` for newlines |

Example:

```text
SSH_PRIVATE_KEY=-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA...\n-----END OPENSSH PRIVATE KEY-----\n
```

### 4. Redeploy and verify

Redeploy after adding the key. The runtime will inject the SSH key during startup so OpenClaw can perform Git operations with that identity.

## Local development

Local development uses the same published image as Lagoon.

### 1. Create the environment file

```bash
cp .env.example .env
```

Set the amazee.ai values in `.env`. You can also add the optional `SLACK_APP_TOKEN`, `SLACK_BOT_TOKEN`, and `SSH_PRIVATE_KEY` variables locally if you want to exercise those integrations through Docker Compose.

### 2. Start the service

```bash
docker compose pull
docker compose up -d
```

The gateway will be available at `http://localhost:3000`.

### 3. View logs

```bash
docker compose logs -f openclaw-gateway
```

### 4. Connect to the container

```bash
docker compose exec openclaw-gateway bash
```

### 5. Stop the service

```bash
docker compose down
```

## Notes

- Runtime state is stored in `./.local` and mounted to `/home/.openclaw`
- The service still runs as UID `10000`
- The shared image keeps amazee.ai discovery, Slack support, and Git SSH bootstrap behavior intact
- If you need a custom derivative image, prefer building a tiny `FROM ghcr.io/amazeeio/openclaw-lagoon-base:latest` image instead of copying this repository again
