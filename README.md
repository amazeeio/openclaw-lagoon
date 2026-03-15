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

## Local development

Local development uses the same published image as Lagoon.

### 1. Create the environment file

```bash
cp .env.example .env
```

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
