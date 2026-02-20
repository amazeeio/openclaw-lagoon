# Stage 1: Install openclaw (skip native builds for local LLM - not needed with API providers)
FROM node:22-bookworm AS builder

# Install git (required by npm for some dependencies)
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Install openclaw globally, skipping postinstall scripts that build native code
# This disables local LLM support (node-llama-cpp) but works fine with API providers like amazeeai
ARG OPENCLAW_VERSION=2026.2.17
RUN npm install -g --ignore-scripts openclaw@${OPENCLAW_VERSION}

# Verify installation
RUN openclaw --version

# Stage 2: Runtime image (smaller, no build tools)
FROM node:22-bookworm-slim

# Install pnpm globally (needed by some openclaw skills)
RUN npm install -g pnpm

# Copy globally installed openclaw from builder and create symlink
COPY --from=builder /usr/local/lib/node_modules/openclaw /usr/local/lib/node_modules/openclaw
RUN ln -s /usr/local/lib/node_modules/openclaw/openclaw.mjs /usr/local/bin/openclaw

# Verify installation
RUN openclaw --version

# Optional: extra Debian packages for browser automation or other needs
ARG EXTRA_APT_PACKAGES=""
RUN apt-get update && apt-get install -y \
    tini \
    git \
    bash \
    curl \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    procps \
    $EXTRA_APT_PACKAGES \
    && rm -rf /var/lib/apt/lists/*

# Create Lagoon directory structure
RUN mkdir -p /lagoon/entrypoints /lagoon/bin /home

# Copy Lagoon utility scripts
COPY .lagoon/fix-permissions /bin/fix-permissions
COPY .lagoon/entrypoints.sh /lagoon/entrypoints.sh
COPY .lagoon/bashrc /home/.bashrc
COPY .lagoon/polydock_claim.sh /lagoon/polydock_claim.sh

# Make scripts executable and set up proper permissions for non-root users
RUN chmod +x /bin/fix-permissions /lagoon/entrypoints.sh /lagoon/polydock_claim.sh && \
    fix-permissions /home

# Copy Lagoon entrypoint scripts
# 05-ssh-key.sh: Automated SSH key setup for container (handles Lagoon and custom environments)
# 50-shell-config.sh: Custom bash prompt with lobster branding
# 60-amazeeai-config.sh: Model discovery from amazee.ai
COPY .lagoon/05-ssh-key.sh /lagoon/entrypoints/05-ssh-key.sh
COPY .lagoon/50-shell-config.sh /lagoon/entrypoints/50-shell-config.sh
COPY .lagoon/60-amazeeai-config.sh /lagoon/entrypoints/60-amazeeai-config.sh
COPY .lagoon/ssh_config /etc/ssh/ssh_config

# Create data directories for persistent config and npm global packages
RUN mkdir -p /home/.openclaw /home/.openclaw/npm \
    && fix-permissions /home/.openclaw

# pnpm and npm configuration - use writable directories to avoid permission issues
# Cache in /tmp (ephemeral), global prefix in /home/.openclaw (persistent)
ENV NODE_ENV=production \
    HOME=/home \
    OPENCLAW_GATEWAY_PORT=3000 \
    XDG_DATA_HOME=/home/.openclaw/.local/share/ \
    PNPM_HOME=/home/.openclaw/.local/share/pnpm \
    npm_config_cache=/tmp/.npm \
    npm_config_prefix=/home/.openclaw/npm \
    PATH="/home/.openclaw/npm/bin:/home/.openclaw/.local/share/pnpm:$PATH" \
    LAGOON=openclaw \
    TMPDIR=/tmp \
    TMP=/tmp \
    BASH_ENV=/home/.bashrc

WORKDIR /home/.openclaw

# Port 3000 already exposed by base image
EXPOSE 3000

# Use Lagoon entrypoint system (tini + entrypoints.sh sources all scripts in /lagoon/entrypoints/*)
ENTRYPOINT ["/usr/bin/tini", "--", "/lagoon/entrypoints.sh"]
CMD ["openclaw", "gateway", "--bind", "lan"]
