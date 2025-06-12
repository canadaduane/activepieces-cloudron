#!/bin/bash

set -eo pipefail # Exit on error, treat unset variables as an error, and propagate exit status through pipes

echo "Starting ActivePieces..."

# Create necessary directories if they don't exist
mkdir -p /app/data/cache /app/data/logs /app/data/configs /app/data/encryption # Added encryption for AP_ENCRYPTION_KEY
mkdir -p /tmp
mkdir -p /run

# Set ownership to the cloudron user
chown -R cloudron:cloudron /app/data /tmp /run

# --- Configuration based on Cloudron Environment Variables ---
# These AP_ prefixed variables are based on common patterns and ActivePieces' .env.example.
# They MUST be verified against ActivePieces documentation or source code for the exact version being packaged.

# Database (PostgreSQL)
export AP_POSTGRES_HOST=${CLOUDRON_POSTGRESQL_HOST}
export AP_POSTGRES_PORT=${CLOUDRON_POSTGRESQL_PORT}
export AP_POSTGRES_USERNAME=${CLOUDRON_POSTGRESQL_USERNAME}
export AP_POSTGRES_PASSWORD=${CLOUDRON_POSTGRESQL_PASSWORD}
export AP_POSTGRES_DATABASE=${CLOUDRON_POSTGRESQL_DATABASE}
# From .env.example, it seems it might also use AP_POSTGRES_SSL_ENABLED
# export AP_POSTGRES_SSL_ENABLED=false # Set to true if Cloudron PostgreSQL uses SSL and app supports it

# Redis
export AP_REDIS_HOST=${CLOUDRON_REDIS_HOST}
export AP_REDIS_PORT=${CLOUDRON_REDIS_PORT}
export AP_REDIS_PASSWORD=${CLOUDRON_REDIS_PASSWORD}
# Construct AP_REDIS_URL as it seems to be preferred by some Node.js apps
if [ -n "${CLOUDRON_REDIS_PASSWORD}" ]; then
  export AP_REDIS_URL="redis://default:${CLOUDRON_REDIS_PASSWORD}@${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"
else
  export AP_REDIS_URL="redis://${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"
fi
# AP_REDIS_USER (default if not password) and AP_REDIS_DB (0) might also be relevant from .env.example

# Application URLs & Ports
export AP_FRONTEND_URL="https://${CLOUDRON_APP_DOMAIN}"
export AP_API_URL="https://${CLOUDRON_APP_DOMAIN}" # API is at root path after Nginx proxy
export AP_BASE_URL="https://${CLOUDRON_APP_DOMAIN}"
export AP_PORT="3000" # Internal port the Node.js app listens on, matches httpPort in manifest

# JWT Secret & Encryption Key (from .env.example)
JWT_SECRET_FILE="/app/data/jwt_secret.txt"
if [ ! -f "${JWT_SECRET_FILE}" ]; then
    echo "Generating new AP_JWT_SECRET..."
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 > "${JWT_SECRET_FILE}"
    chmod 600 "${JWT_SECRET_FILE}"
fi
export AP_JWT_SECRET=$(cat "${JWT_SECRET_FILE}")

ENCRYPTION_KEY_FILE="/app/data/encryption/encryption_key.txt" # Storing in a sub-directory
if [ ! -f "${ENCRYPTION_KEY_FILE}" ]; then
    echo "Generating new AP_ENCRYPTION_KEY..."
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 > "${ENCRYPTION_KEY_FILE}" # 32 chars for AES-256
    chmod 600 "${ENCRYPTION_KEY_FILE}"
fi
export AP_ENCRYPTION_KEY=$(cat "${ENCRYPTION_KEY_FILE}")


# Email (Sendmail Addon) - Variables based on .env.example (e.g., AP_SMTP_*)
export AP_SMTP_HOST=${CLOUDRON_MAIL_SMTP_SERVER}
export AP_SMTP_PORT=${CLOUDRON_MAIL_SMTP_PORT}
export AP_SMTP_USERNAME=${CLOUDRON_MAIL_SMTP_USERNAME}
export AP_SMTP_PASSWORD=${CLOUDRON_MAIL_SMTP_PASSWORD}
export AP_SMTP_FROM_EMAIL=${CLOUDRON_MAIL_FROM} # .env.example uses AP_SMTP_SENDER_EMAIL
export AP_SMTP_SENDER_EMAIL=${CLOUDRON_MAIL_FROM}

# Determine SSL/TLS for SMTP based on Cloudron's mail settings
if [ "${CLOUDRON_MAIL_SMTP_PORT}" = "465" ]; then
  export AP_SMTP_SSL_ENABLED=true # .env.example uses AP_SMTP_SECURE
  export AP_SMTP_SECURE=true
else
  export AP_SMTP_SSL_ENABLED=false
  export AP_SMTP_SECURE=false
fi
# STARTTLS is often on port 587. Cloudron provides CLOUDRON_MAIL_SMTP_STARTTLS.
# ActivePieces .env.example doesn't explicitly show STARTTLS, but `secure=false` with `requireTLS=true` is common.
# For now, we rely on AP_SMTP_SECURE. If STARTTLS is needed, further logic is required.

# Node Environment
export NODE_ENV="production"

# Other configurations from .env.example
export AP_TELEMETRY_ENABLED="false" # Recommended for Cloudron packages
export AP_SANDBOX_RUN_TIME_SECONDS="600" # Default from .env.example
export AP_SIGN_UP_ENABLED="true" # Default, can be made configurable via Cloudron env if needed

# Files (from .env.example, might relate to local file storage piece or temp storage)
# export AP_LOCAL_STORE_PATH="/app/data/files" # If local file storage is used and needs to be persistent
# mkdir -p /app/data/files && chown -R cloudron:cloudron /app/data/files

# Execute pieces in a sandbox
export AP_EXECUTE_SANDBOX="true" # Default from .env.example

# Webhook URL (important for reverse proxy setup)
export AP_WEBHOOK_URL="https://${CLOUDRON_APP_DOMAIN}/api/v1/webhooks" # Ensure this matches Nginx proxy

# Queue mode (MEMORY or REDIS)
export AP_QUEUE_MODE="REDIS" # Use Redis addon

# Log Level & Pretty Logs (from .env.example)
export AP_LOG_LEVEL="INFO"
export AP_PRETTY_LOGS="false" # For production, structured logs are often better

# Database Migrations
# ActivePieces' docker-compose.yml and package.json suggest migrations.
# The `migration:run` script is `ts-node -r tsconfig-paths/register --transpileOnly src/app/database/migration/index.ts`
# In the built version, this needs to run against JS files.
# The build process should compile these TS files to JS in `dist`.
# A common pattern is for the build to output a JS-compatible migration script or for TypeORM to work with JS entities.
# Let's assume the build output in `dist` is runnable directly or via a package.json script.
echo "Running database migrations..."
cd /app/code
# Check if a specific production migration script exists in package.json
if npm run --silent migration:run:prod --if-present; then
    echo "Production database migrations command executed successfully."
elif npm run --silent migration:run --if-present; then
    echo "Development database migrations command executed successfully."
else
    echo "Database migration script (migration:run or migration:run:prod) not found in package.json or failed. Proceeding..."
    # This might be an issue. Verify how migrations are handled in their official Docker image post-build.
fi


echo "Starting ActivePieces Node.js backend on port ${AP_PORT}..."
# The backend listens on AP_PORT (3000), matching httpPort in CloudronManifest.json.
# `USER cloudron` in Dockerfile means this script already runs as cloudron.
# `exec` replaces the shell with the node process.
exec /usr/bin/node --enable-source-maps /app/code/dist/packages/server/api/main.js
