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
const workspaceDir = process.env.OPENCLAW_WORKSPACE || '/home/.openclaw/workspace';
const bundledBootstrapSourceDir = '/lagoon/amazeeai-bootstrap';
const bundledAmazeeBootstrapRelativePath = path.join('amazee', 'AGENTS.md');
const bundledAmazeeBootstrapTargetPath = path.join(workspaceDir, bundledAmazeeBootstrapRelativePath);

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
  tools: {
    profile: 'full',
  },
  gateway: {
    port: gatewayPort,
    mode: 'local',
    controlUi: {
      allowedOrigins: ['http://localhost:3000', 'https://alpha.amazeeclaw.amazee.ai'],
    },
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
  // Config file exists but is invalid - back it up, then start from template.
  if (fs.existsSync(configPath)) {
    try {
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const backupPath = `${configPath}.parse-error-${timestamp}.bak`;
      fs.copyFileSync(configPath, backupPath);
      console.log('[amazeeai-config] Backed up invalid config to:', backupPath);
    } catch (backupError) {
      console.warn('[amazeeai-config] Failed to back up invalid config:', backupError.message);
    }
  }

  console.log('[amazeeai-config] Config parse error, reinitializing from template:', e.message);
  config = JSON.parse(JSON.stringify(configTemplate));
}

// Ensure nested objects exist and required fields are set
config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.agents.defaults.compaction = config.agents.defaults.compaction || {};
config.models = config.models || {};
config.models.providers = config.models.providers || {};
config.tools = config.tools || {};
config.gateway = config.gateway || {};
config.channels = config.channels || {};
config.hooks = config.hooks || {};
config.hooks.internal = config.hooks.internal || {};
config.hooks.internal.entries = config.hooks.internal.entries || {};

if (!config.tools.profile) {
  config.tools.profile = 'full';
  console.log('[amazeeai-config] Set tools.profile to default value: full');
}

// Ensure required base fields from template are present
// OpenClaw needs these to start properly
if (!config.agents.defaults.workspace) {
  config.agents.defaults.workspace = workspaceDir;
  console.log('[amazeeai-config] Set default workspace:', config.agents.defaults.workspace);
}

function ensureBundledBootstrapFiles() {
  const sourcePath = path.join(bundledBootstrapSourceDir, 'AGENTS.md');

  if (!fs.existsSync(sourcePath)) {
    console.warn('[amazeeai-config] Bundled bootstrap source not found:', sourcePath);
    return;
  }

  fs.mkdirSync(path.dirname(bundledAmazeeBootstrapTargetPath), { recursive: true });
  fs.copyFileSync(sourcePath, bundledAmazeeBootstrapTargetPath);
  console.log('[amazeeai-config] Seeded extra bootstrap file:', bundledAmazeeBootstrapTargetPath);
}

function configureExtraBootstrapHooks() {
  config.hooks.internal.enabled = true;
  config.hooks.internal.entries['bootstrap-extra-files'] = {
    enabled: true,
    paths: [bundledAmazeeBootstrapRelativePath],
  };
  console.log('[amazeeai-config] Enabled hooks.internal.entries.bootstrap-extra-files');
}

// Initialize compaction memory flush defaults only when not already configured.
if (!config.agents.defaults.compaction.memoryFlush) {
  config.agents.defaults.compaction.reserveTokensFloor = 20000;
  config.agents.defaults.compaction.memoryFlush = {
    enabled: true,
    softThresholdTokens: 40000,
    prompt: 'Pre-compaction memory flush. Store durable memories now in memory/YYYY-MM-DD.md (create memory/ if needed). If the file already exists, APPEND only and do not overwrite existing entries. Do not create timestamped variant files (for example, YYYY-MM-DD-HHMM.md); always use the canonical YYYY-MM-DD.md filename. Capture only lasting notes: key decisions made, current project status, lessons learned, and active blockers. If there is nothing durable to store, reply with NO_REPLY.'
  };
  console.log('[amazeeai-config] Initialized compaction memory flush defaults');
} else {
  console.log('[amazeeai-config] Existing compaction memory flush config detected; leaving unchanged');
}

// Initialize context pruning defaults only when not already configured.
if (!config.agents.defaults.contextPruning) {
  config.agents.defaults.contextPruning = {
    mode: 'cache-ttl',
    ttl: '6h',
    keepLastAssistants: 3,
  };
  console.log('[amazeeai-config] Initialized context pruning defaults');
} else {
  console.log('[amazeeai-config] Existing context pruning config detected; leaving unchanged');
}

// Initialize memory search defaults only when not already configured.
if (!config.agents.defaults.memorySearch) {
  config.agents.defaults.memorySearch = {
    experimental: {
      sessionMemory: true,
    },
    sources: ['memory', 'sessions'],
  };
  console.log('[amazeeai-config] Initialized memory search defaults');
} else {
  console.log('[amazeeai-config] Existing memory search config detected; leaving unchanged');
}

// Initialize memory search hybrid query defaults only when not already configured.
if (!config.agents.defaults.memorySearch.query?.hybrid) {
  config.agents.defaults.memorySearch.query = config.agents.defaults.memorySearch.query || {};
  config.agents.defaults.memorySearch.query.hybrid = {
    enabled: true,
    vectorWeight: 0.7,
    textWeight: 0.3,
  };
  console.log('[amazeeai-config] Initialized memory search hybrid query defaults');
} else {
  console.log('[amazeeai-config] Existing memory search hybrid query config detected; leaving unchanged');
}

if (!config.gateway.port) {
  config.gateway.port = gatewayPort;
}
if (!config.gateway.mode) {
  config.gateway.mode = 'local';
}
if (!config.gateway.controlUi) {
  config.gateway.controlUi = {};
}

// Always set allowed origins at startup to ensure secure defaults are enforced.
const parseLagoonRoutes = (rawRoutes) => {
  if (!rawRoutes || typeof rawRoutes !== 'string') {
    return [];
  }

  return rawRoutes
    .split(',')
    .map(route => route.trim())
    .filter(Boolean)
    .map(route => route.replace(/\/+$/, ''))
    .map(route => {
      if (/^https?:\/\//i.test(route)) {
        return route;
      }
      return `https://${route}`;
    });
};

const fixedAllowedOrigins = [
  'http://localhost:3000',
  'https://alpha.amazeeclaw.amazee.ai',
];

const lagoonRouteOrigins = parseLagoonRoutes(process.env.LAGOON_ROUTES || '');
config.gateway.controlUi.allowedOrigins = Array.from(new Set([
  ...fixedAllowedOrigins,
  ...lagoonRouteOrigins,
]));
console.log('[amazeeai-config] Set gateway.controlUi.allowedOrigins to:', config.gateway.controlUi.allowedOrigins.join(', '));



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

    const response = await fetch(`${baseUrl}/v1/model/info`, { headers });

    if (!response.ok) {
      console.error(`[amazeeai-config] Failed to fetch model info: ${response.status} ${response.statusText}`);
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

    console.log(`[amazeeai-config] Discovered ${data.data.length} models from /v1/model/info:`);
    for (const m of data.data) {
      const id = m.model_name || m.model_info?.key || m.litellm_params?.model || '(unknown)';
      console.log(`[amazeeai-config]   - ${id}`);
    }

    const toNumberOr = (value, fallback) => {
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
      return fallback;
    };

    const isReasoningModel = (modelName, info) => {
      if (info?.supports_reasoning === true) {
        return true;
      }
      const supportedParams = Array.isArray(info?.supported_openai_params) ? info.supported_openai_params : [];
      if (supportedParams.includes('thinking') || supportedParams.includes('reasoning_effort')) {
        return true;
      }
      return false;
    };

    const deriveInputTypes = (info) => {
      const mode = info?.mode;
      const inputTypes = ['text'];
      if (mode === 'embedding') {
        return inputTypes;
      }
      if (info?.supports_vision === true) {
        inputTypes.push('image');
      }
      return inputTypes;
    };

    // Transform models to OpenClaw format from /v1/model/info payload
    const models = data.data.map(m => {
      const info = m.model_info || {};
      const modelName = m.model_name || info.key || m.litellm_params?.model || '';

      const contextWindow = toNumberOr(info.max_input_tokens, toNumberOr(info.max_tokens, 128000));
      const maxTokens = toNumberOr(info.max_output_tokens, toNumberOr(info.max_tokens, 4096));

      return {
        id: modelName,
        name: modelName,
        reasoning: isReasoningModel(modelName, info),
        input: deriveInputTypes(info),
        cost: {
          input: toNumberOr(info.input_cost_per_token, 0),
          output: toNumberOr(info.output_cost_per_token, 0),
          cacheRead: toNumberOr(info.cache_read_input_token_cost, 0),
          cacheWrite: toNumberOr(info.cache_creation_input_token_cost, 0),
        },
        contextWindow,
        maxTokens,
      };
    }).filter(m => m.id);

    if (models.length === 0) {
      console.log('[amazeeai-config] No valid models after filtering');
      return;
    }

    // Configure the amazeeai provider
    // baseUrl and apiKey are injected directly so runtime refresh scripts can
    // materialize claim-time environment labels into openclaw.json.
    const providerConfig = {
      baseUrl: baseUrl,
      api: 'openai-completions',
      models: models,
    };

    if (apiKey) {
      providerConfig.apiKey = apiKey;
    }

    config.models.providers.amazeeai = providerConfig;
    console.log('[amazeeai-config] Added amazeeai provider with', models.length, 'models');

    // Replace allowlist for /model picker with discovered models only.
    // This removes stale model entries from previous runs.
    const discoveredAllowlist = {};
    for (const model of models) {
      discoveredAllowlist[`amazeeai/${model.id}`] = {};
    }
    config.agents.defaults.models = discoveredAllowlist;

    // If AMAZEEAI_DEFAULT_MODEL is set, force it as primary model.
    // If not set, leave default model config untouched.
    const modelIds = models.map(m => m.id);
    if (defaultModel) {
      const requestedPrimaryModel = `amazeeai/${defaultModel}`;
      if (modelIds.includes(defaultModel)) {
        config.agents.defaults.model.primary = requestedPrimaryModel;
        console.log('[amazeeai-config] Set default primary model from AMAZEEAI_DEFAULT_MODEL:', requestedPrimaryModel);
      } else {
        console.warn(`[amazeeai-config] Warning: AMAZEEAI_DEFAULT_MODEL "${defaultModel}" not found in discovered models`);
        console.warn('[amazeeai-config] Available models:', modelIds.join(', '));
      }
    } else {
      console.log('[amazeeai-config] No AMAZEEAI_DEFAULT_MODEL set; leaving default model config unchanged');
    }

  } catch (error) {
    console.error('[amazeeai-config] Model discovery failed:', error.message);
  }
}

function hasAmazeeaiEmbeddingsModel() {
  const models = config.models?.providers?.amazeeai?.models;
  if (!Array.isArray(models) || models.length === 0) {
    return false;
  }

  return models.some(model => {
    const mode = String(model?.mode || model?.type || '').toLowerCase();
    if (mode === 'embedding' || mode === 'embeddings') {
      return true;
    }

    const idAndName = `${model?.id || ''} ${model?.name || ''}`.toLowerCase();
    return /\bembed(ding|dings)?\b/.test(idAndName);
  });
}

function configureMemorySearchRemoteFromAmazeeai() {
  if (!hasAmazeeaiEmbeddingsModel()) {
    console.warn('[amazeeai-config] Skipping memorySearch remote override: embeddings model not found in amazeeai provider');
    return;
  }

  // Configure remote memory-search embeddings from amazee.ai env vars.
  // These values are intentionally overwritten on each run.
  const memorySearchBaseUrl = (process.env.AMAZEEAI_BASE_URL || '').replace(/\/+$/, '');
  const memorySearchApiKey = process.env.AMAZEEAI_API_KEY || '';
  config.agents.defaults.memorySearch = config.agents.defaults.memorySearch || {};
  config.agents.defaults.memorySearch.provider = 'openai';
  config.agents.defaults.memorySearch.model = 'embeddings';
  config.agents.defaults.memorySearch.remote = {
    baseUrl: memorySearchBaseUrl ? `${memorySearchBaseUrl}/v1/` : '',
    apiKey: memorySearchApiKey,
  };
  console.log('[amazeeai-config] Configured memorySearch for amazee.ai embeddings model');
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

function sanitizeModelInputs() {
  const allowedInputs = new Set(['text', 'image']);
  const providers = config.models?.providers;
  if (!providers || typeof providers !== 'object') {
    return;
  }

  let sanitizedCount = 0;
  for (const provider of Object.values(providers)) {
    if (!provider || !Array.isArray(provider.models)) {
      continue;
    }
    for (const model of provider.models) {
      const originalInput = Array.isArray(model.input) ? model.input : ['text'];
      const sanitizedInput = originalInput.filter(value => allowedInputs.has(value));
      const uniqueInput = Array.from(new Set(sanitizedInput));
      const finalInput = uniqueInput.length > 0 ? uniqueInput : ['text'];

      const changed = finalInput.length !== originalInput.length
        || finalInput.some((value, idx) => value !== originalInput[idx]);

      if (changed) {
        model.input = finalInput;
        sanitizedCount += 1;
      }
    }
  }

  if (sanitizedCount > 0) {
    console.log(`[amazeeai-config] Sanitized input types for ${sanitizedCount} model(s) to OpenClaw-supported values`);
  }
}

// ============================================================
// MAIN
// ============================================================
async function main() {
  ensureBundledBootstrapFiles();
  await discoverModels();
  configureMemorySearchRemoteFromAmazeeai();
  configureGatewayToken();
  configureChannels();
  configureExtraBootstrapHooks();
  sanitizeModelInputs();

  // Write updated config
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log('[amazeeai-config] Configuration saved to:', configPath);
}

main().catch(err => {
  console.error('[amazeeai-config] Fatal error:', err);
  process.exit(1);
});
EOFNODE

echo "[amazeeai-config] Configuration complete. Starting OpenClaw gateway..."
echo "[amazeeai-config] Note: OpenClaw may take a moment to initialize (no output is normal)."
