#!/bin/sh
# Polydock post-deploy helper: ensure required OpenClaw gateway settings exist.

echo "[polydock-post-deploy] Applying OpenClaw post-deploy config..."

node << 'EOFNODE'
const fs = require('fs');
const path = require('path');

const stateDir = process.env.OPENCLAW_STATE_DIR || path.join(process.env.HOME || '/home', '.openclaw');
const configPath = path.join(stateDir, 'openclaw.json');

fs.mkdirSync(stateDir, { recursive: true });

let config = {};
try {
  if (fs.existsSync(configPath)) {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  }
} catch (error) {
  console.log('[polydock-post-deploy] Config parse error, starting from empty object:', error.message);
  config = {};
}

config.gateway = config.gateway || {};
config.gateway.controlUi = config.gateway.controlUi || {};
config.gateway.controlUi.dangerouslyDisableDeviceAuth = true;

fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('[polydock-post-deploy] Ensured gateway.controlUi.dangerouslyDisableDeviceAuth = true');
console.log('[polydock-post-deploy] Configuration saved to:', configPath);
EOFNODE
