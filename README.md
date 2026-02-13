# OpenClaw for Lagoon

This repository enables [OpenClaw](https://openclaw.ai/) to run on the Lagoon platform. By running OpenClaw in a containerized environment, you gain significantly improved security compared to traditional installations. With containerization, you have tight control over exactly what OpenClaw has access to, unlike a regular installation on a computer where it has unrestricted access to everything on the system.

## Features

- **Enhanced Security**: Containerized deployment with controlled access to system resources
- **Easy Deployment**: Works out of the box with minimal configuration
- **Lagoon Integration**: Seamless integration with Lagoon's platform features
- **API-Based**: Uses external LLM API providers (no local model required)

## Prerequisites

- A Lagoon account with access to create repositories
- Access to an LLM API provider (e.g., amazee.ai with outodiscovery, other model providers also work but need to be manually configured)

## Installation

### 1. Add Repository to Lagoon

Add this repository to your Lagoon platform as a new project. The container will work out of the box with default settings.

### 2. Configure Environment Variables

Before deploying, you need to configure three environment variables in your Lagoon project:

| Variable | Description | Example |
|----------|-------------|---------|
| `AMAZEEAI_BASE_URL` | The base URL for your LLM API provider | `https://llm.us104.amazee.ai` |
| `AMAZEEAI_API_KEY` | Your API key for authentication | `your-api-key-here` |
| `AMAZEEAI_DEFAULT_MODEL` | The default LLM model to use | `claude-4-5-sonnet` |

**How to set environment variables in Lagoon:**

You can set these variables through the Lagoon UI or CLI before deployment. Refer to your Lagoon documentation for the specific method for your platform.

### 3. Deploy

Deploy your project for the first time. Lagoon will build the container and start the OpenClaw gateway.

### 4. Connect via SSH

After deployment, connect to the container via SSH:

```bash
lagoon ssh -p [projectname] -e [environmentname] -s openclaw-gateway
```

_(Screenshot placeholder - to be added)_

### 5. Get the Dashboard URL

Once connected to the SSH session, OpenClaw will display a URL in the terminal output. This URL contains a unique token to access the dashboard, without the token the Dashboard will not work at all.

**Copy this URL** - you'll need it in the next step.

### 6. Visit the Dashboard URL

Open the URL in your browser. The page will display a message indicating that the pairing needs to be configured.

### 7. Approve the Device

Go back to your SSH session in the container and run:

```bash
openclaw devices list
```

You should see one pending connection listed. Note the request ID, then approve it:

```bash
openclaw devices approve <request_id>
```

Replace `<request_id>` with the actual ID shown in the list.

### 8. Start Chatting

Return to your browser and type `hello` to the bot.

OpenClaw will now initiate itself, ask configuration questions, and begin setting itself up. You're ready to start using OpenClaw on Lagoon!

## amazee.ai Model Discovery

When you configure the `AMAZEEAI_BASE_URL` and `AMAZEEAI_API_KEY` environment variables, the container automatically performs **model discovery** at startup. This feature simplifies model configuration by dynamically detecting what models your API key has access to.

### How It Works

On container startup, the `.lagoon/60-amazeeai-config.sh` script:

1. **Queries the amazee.ai API** - Makes a request to `/v1/models` endpoint using your API credentials
2. **Discovers Available Models** - Retrieves the complete list of models your API key can access
3. **Auto-configures OpenClaw** - Automatically injects all discovered models into OpenClaw's configuration
4. **Sets the Default Model** - Configures the `AMAZEEAI_DEFAULT_MODEL` as the primary model (if specified and available)

### Benefits

- **No Manual Configuration** - No need to manually list or configure individual models
- **Always Up-to-Date** - Automatically reflects any model access changes in your API account
- **Dynamic Access Control** - OpenClaw only sees models your API key has permission to use
- **Seamless Updates** - When new models are added to your account, simply restart the container to discover them

### Startup Logs

During container startup, you'll see logs like this:

```
[amazeeai-config] Discovering models from: https://llm.us104.amazee.ai
[amazeeai-config] Discovered 5 models:
[amazeeai-config]   - claude-4-5-sonnet
[amazeeai-config]   - claude-4-opus
[amazeeai-config]   - gpt-4o
[amazeeai-config]   - gpt-4o-mini
[amazeeai-config]   - o1
[amazeeai-config] Set default model to: amazeeai/claude-4-5-sonnet
```

All discovered models will be available in OpenClaw's model picker and can be selected during conversations.

## Slack Integration (Optional)

OpenClaw can be integrated with Slack to provide an AI assistant directly in your workspace. For detailed setup instructions, refer to the [official OpenClaw Slack documentation](https://docs.openclaw.ai/channels/slack).

### Quick Setup Guide

**1. Create a Slack App**

Create a new Slack app from a manifest using the following configuration. **Important**: Before using this manifest, customize the following placeholders:
- Replace `YOUR_BOT_NAME` with your desired bot name
- Replace `YOUR_BOT_DESCRIPTION` with a description of your bot's purpose
- Adjust the `assistant_description` to match your bot's specific capabilities

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

**2. Generate Tokens**

After creating your Slack app:
- Configure the app with the basics like a color, bot icon, and description
- On the "Basic Information" tab, generate an **App-Level Token** with scope "connections:write" (the token starts with `xapp-`)
- Install the app to your workspace to get the **Bot User OAuth Token** (starts with `xoxb-`)

**3. Configure Lagoon Environment Variables**

Add the following two environment variables to your Lagoon project:

| Variable | Description | Example |
|----------|-------------|---------|
| `SLACK_APP_TOKEN` | App-level token for Socket Mode | `xapp-1-A123...` |
| `SLACK_BOT_TOKEN` | Bot user OAuth token | `xoxb-123...` |

**4. Redeploy**

Redeploy your Lagoon project with the new environment variables. OpenClaw will automatically detect the Slack tokens and configure itself to work with Slack.

**5. Test Your Bot**

Once deployed, you can send it a direct message. Using the WebUI, you can ask your bot to confirm Slack is ready to roll.

Heads up, as with the WebUI you will need to approve the pairing. Once you have confirmed the Slack integration is running using the WebUI chat, your can send a DM on Slack, and you'll get an authorization code and instructions to run in the terminal using the lagoon ssh connection as before.

First shell into your lagoon project as before..

```bash
lagoon ssh -p [projectname] -e [environmentname] -s openclaw-gateway
```

Next you can approve your connection based on the code the bot provided you in the Slack message.

```bash
openclaw pairing approve slack <code>
```

If you want to use the Bot in channel, you need to add it to the channel and enable the channel via telling it to enable it through a direct message. See the official [official OpenClaw Slack documentation](https://docs.openclaw.ai/channels/slack) for more information.

## Git Repository Access (Optional)

OpenClaw can be configured to clone and push to Git repositories by providing an SSH private key. This enables the bot to interact with version control systems like GitHub, GitLab, or Bitbucket.

### Security Best Practices

**⚠️ Important Security Note:**
- **DO NOT** use your personal SSH private key for this purpose
- **Always** create a dedicated SSH key pair specifically for the bot
- **Limit** the key's access to only the repositories and permissions the bot needs
- Configure the key as a **deploy key** in GitHub/GitLab with minimal permissions (read-only if the bot only needs to clone, read-write if it needs to push)

### Creating a Dedicated SSH Key

Generate a new SSH key pair specifically for OpenClaw:

```bash
# Generate a new SSH key (use a descriptive name)
ssh-keygen -t ed25519 -C "openclaw-bot@your-domain.com" -f ~/.ssh/openclaw_bot

# This creates two files:
# - openclaw_bot (private key - keep secret!)
# - openclaw_bot.pub (public key - add to GitHub/GitLab)
```

Add the **public key** (`openclaw_bot.pub`) to your Git provider:
- **GitHub**: Settings → Deploy keys (per repository) or SSH keys (for your account)
- **GitLab**: Settings → Repository → Deploy Keys
- **Bitbucket**: Repository settings → Access keys

### Formatting the Private Key for Lagoon

The private key must be formatted as a single-line string with newlines replaced by `\n`:

```bash
# Convert the private key to the required format
awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' ~/.ssh/openclaw_bot
```

The output should look like this:

```
-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\n...more lines...\nQzI1NTE5AAAAIGExample==\n-----END OPENSSH PRIVATE KEY-----\n
```

### Configure the Environment Variable

Add the formatted private key as an environment variable in Lagoon:

| Variable | Description | Format |
|----------|-------------|--------|
| `SSH_PRIVATE_KEY` | OpenSSH private key for Git operations | Single-line string with `\n` for newlines |

**Example:**
```
SSH_PRIVATE_KEY=-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA...\n-----END OPENSSH PRIVATE KEY-----\n
```

### Redeploy and Verify

After adding the environment variable, redeploy your Lagoon project. The container will automatically inject the SSH key, allowing OpenClaw to perform Git operations.

To verify the setup, ask OpenClaw to clone a repository or check Git access through the chat interface.

## Setting up Brave for Web Search (Optional)

If you want OpenClaw to search the web using Brave, you're going to need a Brave API key.

If you don't already have a Brave account, head over to http://brave.com/search/api/ and click "Get Started". Following the standard signup steps, and be sure to register for at least a "Free" account. Note, you will need a credit card with at least 1 USD available to get the Free tier going.

Once you have a Brave account, head over to https://api-dashboard.search.brave.com/app/keys and create an API Key. Copy the new key, and create a Lagoon variable called "BRAVE_API_KEY" as you did before.

Redploy your Lagoon project to get rolling with search.


## Local Development

You can run OpenClaw locally using Docker Compose without needing to deploy to Lagoon. This is useful for testing, debugging, or developing new features for this repository.

### Setup for Local Development

**1. Copy the Environment File**

Create a `.env` file from the example:

```bash
cp .env.example .env
```

**2. Configure Environment Variables**

Edit the `.env` file and set your values:

```bash
# Amazee.ai LLM API
AMAZEEAI_BASE_URL=https://llm.us104.amazee.ai
AMAZEEAI_API_KEY=your-api-key-here
AMAZEEAI_DEFAULT_MODEL=claude-4-5-sonnet

# Optional: Slack integration
# SLACK_APP_TOKEN=xapp-1-A123...
# SLACK_BOT_TOKEN=xoxb-123...

# Optional: Git repository access
# SSH_PRIVATE_KEY=-----BEGIN OPENSSH PRIVATE KEY-----\n...
```

**3. Start the Container**

Run OpenClaw using Docker Compose:

```bash
docker-compose up -d
```

The gateway will be available at `http://localhost:3000`

**4. View Logs (Optional)**

Monitor the container logs to see the startup process:

```bash
docker-compose logs -f openclaw-gateway
```

**5. Connect to the Container**

Connect to the running container to get the dashboard URL with the authentication token:

```bash
docker compose exec openclaw-gateway bash
```

Once connected, the URL with the token will be displayed in the terminal. Copy the full URL.

**6. Access the Dashboard**

Open the copied URL in your browser. You'll need to approve the device pairing as described in the installation steps above (`openclaw devices list` and `openclaw devices approve`).

**7. Stop the Container**

When you're done:

```bash
docker-compose down
```

### Local Development Notes

- The `.env` file is git-ignored and won't be committed
- Local configuration is stored in `./.local` directory (also git-ignored)
- The container runs on port 3000 by default (configurable in `docker-compose.yml`)
- All features work the same locally as they do in Lagoon, including:
  - amazee.ai model discovery
  - Slack integration (if tokens are configured)
  - Git repository access (if SSH key is configured)
- Perfect for testing changes to configuration scripts, entrypoints, or Dockerfile modifications

## Architecture

This deployment uses a multi-stage Docker build:

1. **Builder stage**: Installs OpenClaw with optimizations for API-based usage (skips local LLM compilation)
2. **Runtime stage**: Minimal production image with only necessary dependencies

The container includes:
- OpenClaw gateway running on port 3000
- Automated SSH key setup for Lagoon
- Custom shell configuration
- Model discovery from Amazee.ai
- Persistent storage for OpenClaw configuration at `/home/.openclaw`

## Configuration Files

- `.lagoon.yml` - Lagoon deployment configuration
- `docker-compose.yml` - Local development setup
- `.env.example` - Example environment variables
- `.lagoon/05-ssh-key.sh` - SSH key setup automation
- `.lagoon/50-shell-config.sh` - Custom shell prompt
- `.lagoon/60-amazeeai-config.sh` - Model discovery script

## Support

For issues related to:
- **OpenClaw itself**: Visit [OpenClaw documentation](https://openclaw.ai/)
- **Lagoon deployment**: Contact your Lagoon administrator
- **This container setup**: Open an issue in this repository

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

OpenClaw is also MIT licensed.
