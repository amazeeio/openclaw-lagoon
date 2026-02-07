#!/bin/sh
# Lagoon entrypoint: Configure OpenClaw from environment variables
# Discovers models from amazee.ai API when AMAZEEAI_BASE_URL is set; otherwise
# writes a minimal config so the container can start without amazee.ai.

echo "[amazeeai-config] Configuring OpenClaw..."

node << 'EOFNODE'
const fs = require('fs');
const path = require('path');

// Config paths - use OPENCLAW_STATE_DIR if set, otherwise default to home directory
const stateDir = process.env.OPENCLAW_STATE_DIR || path.join(process.env.HOME || '/home', '.openclaw');
const configPath = path.join(stateDir, 'openclaw.json');

console.log('[amazeeai-config] Config path:', configPath);

// Ensure config directory exists
fs.mkdirSync(stateDir, { recursive: true });

// Minimal config template - OpenClaw requires certain base fields to start properly
// Based on: https://github.com/CrocSwap/clawdbot-docker/blob/main/openclaw.json.template
const gatewayPort = parseInt(process.env.OPENCLAW_GATEWAY_PORT, 10) || 18789;
const configTemplate = {
  agents: {
    defaults: {
      workspace: process.env.OPENCLAW_WORKSPACE || '/home/.openclaw/workspace'
    }
  },
  gateway: {
    port: gatewayPort,
    mode: 'local'
  }
};

// Load existing config or initialize from template
let config = {};
try {
  if (fs.existsSync(configPath)) {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    console.log('[amazeeai-config] Loaded existing config');
  } else {
    // No config exists - initialize from template
    config = JSON.parse(JSON.stringify(configTemplate));
    console.log('[amazeeai-config] No existing config found, initializing from template');
  }
} catch (e) {
  // Config file exists but is invalid - start from template
  console.log('[amazeeai-config] Config parse error, reinitializing from template:', e.message);
  config = JSON.parse(JSON.stringify(configTemplate));
}

// Ensure nested objects exist and required fields are set
config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.models = config.models || {};
config.models.providers = config.models.providers || {};
config.gateway = config.gateway || {};
config.channels = config.channels || {};

// Ensure required base fields from template are present
// OpenClaw needs these to start properly
if (!config.agents.defaults.workspace) {
  config.agents.defaults.workspace = process.env.OPENCLAW_WORKSPACE || '/home/.openclaw/workspace';
  console.log('[amazeeai-config] Set default workspace:', config.agents.defaults.workspace);
}
if (!config.gateway.port) {
  config.gateway.port = gatewayPort;
}
if (!config.gateway.mode) {
  config.gateway.mode = 'local';
}

// ============================================================
// AMAZEEAI MODEL DISCOVERY
// ============================================================
async function discoverModels() {
  const baseUrl = (process.env.AMAZEEAI_BASE_URL || '').replace(/\/+$/, '');
  const apiKey = process.env.AMAZEEAI_API_KEY || '';
  const defaultModel = process.env.AMAZEEAI_DEFAULT_MODEL || '';

  if (!baseUrl) {
    console.log('[amazeeai-config] No AMAZEEAI_BASE_URL set, skipping model discovery');
    return;
  }

  console.log('[amazeeai-config] Discovering models from:', baseUrl);

  try {
    const headers = { 'Content-Type': 'application/json' };
    if (apiKey) {
      headers['Authorization'] = `Bearer ${apiKey}`;
    }

    const response = await fetch(`${baseUrl}/v1/models`, { headers });

    if (!response.ok) {
      console.error(`[amazeeai-config] Failed to fetch models: ${response.status} ${response.statusText}`);
      return;
    }

    const data = await response.json();

    if (!data.data || !Array.isArray(data.data)) {
      console.error('[amazeeai-config] Invalid response format: expected { data: [...] }');
      return;
    }

    if (data.data.length === 0) {
      console.log('[amazeeai-config] No models returned from API');
      return;
    }

    console.log(`[amazeeai-config] Discovered ${data.data.length} models:`);
    for (const m of data.data) {
      const id = m.id || m.model || '(unknown)';
      const ownedBy = m.owned_by ? ` (${m.owned_by})` : '';
      console.log(`[amazeeai-config]   - ${id}${ownedBy}`);
    }

    // Transform models to OpenClaw format
    const models = data.data.map(m => {
      const id = m.id || m.model || '';
      return {
        id,
        name: id,
        reasoning: /reasoning|thinking|o1|o3/i.test(id),
        input: ['text'],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 128000,
        maxTokens: 4096,
      };
    }).filter(m => m.id);

    if (models.length === 0) {
      console.log('[amazeeai-config] No valid models after filtering');
      return;
    }

    // Configure the amazeeai provider
    // baseUrl is injected directly, apiKey uses env var reference for security
    const providerConfig = {
      baseUrl: baseUrl,
      api: 'anthropic-messages',
      models: models,
    };

    if (apiKey) {
      providerConfig.apiKey = '${AMAZEEAI_API_KEY}';
    }

    config.models.providers.amazeeai = providerConfig;
    console.log('[amazeeai-config] Added amazeeai provider with', models.length, 'models');

    // Add models to the allowlist for /model picker
    config.agents.defaults.models = config.agents.defaults.models || {};
    for (const model of models) {
      const key = `amazeeai/${model.id}`;
      if (!config.agents.defaults.models[key]) {
        config.agents.defaults.models[key] = {};
      }
    }

    // Set default model if specified and found
    const modelIds = models.map(m => m.id);
    if (defaultModel) {
      if (modelIds.includes(defaultModel)) {
        config.agents.defaults.model.primary = `amazeeai/${defaultModel}`;
        console.log('[amazeeai-config] Set default model to:', `amazeeai/${defaultModel}`);
      } else {
        console.warn(`[amazeeai-config] Warning: AMAZEEAI_DEFAULT_MODEL "${defaultModel}" not found in discovered models`);
        console.warn('[amazeeai-config] Available models:', modelIds.join(', '));
        // Use first model as fallback
        if (models.length > 0) {
          config.agents.defaults.model.primary = `amazeeai/${models[0].id}`;
          console.log('[amazeeai-config] Using first model as default:', `amazeeai/${models[0].id}`);
        }
      }
    } else if (models.length > 0 && !config.agents.defaults.model.primary) {
      // No default specified and none configured - use first discovered model
      config.agents.defaults.model.primary = `amazeeai/${models[0].id}`;
      console.log('[amazeeai-config] No default specified, using first model:', `amazeeai/${models[0].id}`);
    }

  } catch (error) {
    console.error('[amazeeai-config] Model discovery failed:', error.message);
  }
}

// ============================================================
// GATEWAY TOKEN CONFIGURATION
// ============================================================
function configureGatewayToken() {
  const crypto = require('crypto');

  // If OPENCLAW_GATEWAY_TOKEN env var is set, OpenClaw uses it directly
  // No need to write to config - it takes precedence over config value
  if (process.env.OPENCLAW_GATEWAY_TOKEN) {
    console.log('[amazeeai-config] Gateway token set via OPENCLAW_GATEWAY_TOKEN env var');
    return;
  }

  // Check if token already exists in config
  const existingToken = config.gateway?.auth?.token;
  if (existingToken && typeof existingToken === 'string' && existingToken.trim().length > 0) {
    console.log('[amazeeai-config] Gateway token already configured');
    return;
  }

  // Auto-generate a token and save to config (same format as OpenClaw uses)
  const generatedToken = crypto.randomBytes(24).toString('hex');
  config.gateway.auth = config.gateway.auth || {};
  config.gateway.auth.token = generatedToken;
  console.log('[amazeeai-config] Auto-generated gateway token:', generatedToken);
  console.log('[amazeeai-config] Use this token to connect to the gateway');
}

// ============================================================
// CHANNEL CONFIGURATION (from environment variables)
// Using ${VAR_NAME} references - OpenClaw substitutes at load time
// ============================================================
function configureChannels() {
  // Telegram configuration
  if (process.env.TELEGRAM_BOT_TOKEN) {
    config.channels.telegram = config.channels.telegram || {};
    config.channels.telegram.botToken = '${TELEGRAM_BOT_TOKEN}';
    config.channels.telegram.enabled = true;
    config.channels.telegram.dmPolicy = process.env.TELEGRAM_DM_POLICY || 'pairing';
    console.log('[amazeeai-config] Configured Telegram channel');
  }

  // Discord configuration
  if (process.env.DISCORD_BOT_TOKEN) {
    config.channels.discord = config.channels.discord || {};
    config.channels.discord.token = '${DISCORD_BOT_TOKEN}';
    config.channels.discord.enabled = true;
    config.channels.discord.dm = config.channels.discord.dm || {};
    config.channels.discord.dm.policy = process.env.DISCORD_DM_POLICY || 'pairing';
    console.log('[amazeeai-config] Configured Discord channel');
  }

  // Slack configuration
  if (process.env.SLACK_BOT_TOKEN && process.env.SLACK_APP_TOKEN) {
    config.channels.slack = config.channels.slack || {};
    config.channels.slack.botToken = '${SLACK_BOT_TOKEN}';
    config.channels.slack.appToken = '${SLACK_APP_TOKEN}';
    config.channels.slack.enabled = true;
    console.log('[amazeeai-config] Configured Slack channel');
  }
}

// ============================================================
// MAIN
// ============================================================
async function main() {
  await discoverModels();
  configureGatewayToken();
  configureChannels();

  // Write updated config
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log('[amazeeai-config] Configuration saved to:', configPath);
}

main().catch(err => {
  console.error('[amazeeai-config] Fatal error:', err);
  process.exit(1);
});
EOFNODE
