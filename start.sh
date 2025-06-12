#!/bin/bash

set -eo pipefail # Exit on error, treat unset variables as an error, and propagate exit status through pipes

echo "Starting ActivePieces Cloudron container..."

# Create necessary directories if they don't exist
mkdir -p /app/data/cache /app/data/logs /app/data/configs /app/data/encryption /app/data/files
mkdir -p /tmp
mkdir -p /run

# Set ownership to the cloudron user
# Note: /run/supervisord.pid will be created by root if supervisord runs as root.
# Other files in /run created by gosu-ed processes will be owned by cloudron.
chown -R cloudron:cloudron /app/data /tmp

# --- Configuration based on Cloudron Environment Variables (from existing start.sh) ---
echo "Setting up environment variables for ActivePieces..."

# Database (PostgreSQL)
export AP_POSTGRES_HOST=${CLOUDRON_POSTGRESQL_HOST}
export AP_POSTGRES_PORT=${CLOUDRON_POSTGRESQL_PORT}
export AP_POSTGRES_USERNAME=${CLOUDRON_POSTGRESQL_USERNAME}
export AP_POSTGRES_PASSWORD=${CLOUDRON_POSTGRESQL_PASSWORD}
export AP_POSTGRES_DATABASE=${CLOUDRON_POSTGRESQL_DATABASE}
if [ "${CLOUDRON_POSTGRESQL_SSLMODE}" == "require" ] || [ "${CLOUDRON_POSTGRESQL_SSLMODE}" == "verify-full" ]; then
  export AP_POSTGRES_SSL_ENABLED="true"
else
  export AP_POSTGRES_SSL_ENABLED="false"
fi

# Redis
export AP_REDIS_HOST=${CLOUDRON_REDIS_HOST}
export AP_REDIS_PORT=${CLOUDRON_REDIS_PORT}
if [ -n "${CLOUDRON_REDIS_PASSWORD}" ]; then
  export AP_REDIS_PASSWORD=${CLOUDRON_REDIS_PASSWORD}
  export AP_REDIS_URL="redis://default:${CLOUDRON_REDIS_PASSWORD}@${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"
else
  export AP_REDIS_URL="redis://${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"
fi

# Application URLs & Ports
export AP_BASE_URL="https://${CLOUDRON_APP_DOMAIN}"
export AP_FRONTEND_URL="${AP_BASE_URL}"
export AP_WEBHOOK_URL="${AP_BASE_URL}/api/v1/webhooks"
export AP_PORT="3000" # Internal port the Node.js app (ActivePieces backend) listens on

# JWT Secret & Encryption Key
JWT_SECRET_FILE="/app/data/configs/jwt_secret.txt" # Changed path to /app/data/configs
ENCRYPTION_KEY_FILE="/app/data/configs/encryption_key.txt" # Changed path to /app/data/configs
mkdir -p /app/data/configs # Ensure configs directory exists

if [ ! -f "${JWT_SECRET_FILE}" ]; then
    echo "Generating new AP_JWT_SECRET..."
    openssl rand -hex 32 > "${JWT_SECRET_FILE}"
    chown cloudron:cloudron "${JWT_SECRET_FILE}"
    chmod 600 "${JWT_SECRET_FILE}"
fi
export AP_JWT_SECRET=$(cat "${JWT_SECRET_FILE}")

if [ ! -f "${ENCRYPTION_KEY_FILE}" ]; then
    echo "Generating new AP_ENCRYPTION_KEY..."
    openssl rand -hex 32 > "${ENCRYPTION_KEY_FILE}"
    chown cloudron:cloudron "${ENCRYPTION_KEY_FILE}"
    chmod 600 "${ENCRYPTION_KEY_FILE}"
fi
export AP_ENCRYPTION_KEY=$(cat "${ENCRYPTION_KEY_FILE}")

# Email (Sendmail Addon)
export AP_SMTP_HOST=${CLOUDRON_MAIL_SMTP_SERVER}
export AP_SMTP_PORT=${CLOUDRON_MAIL_SMTP_PORT}
export AP_SMTP_USERNAME=${CLOUDRON_MAIL_SMTP_USERNAME}
export AP_SMTP_PASSWORD=${CLOUDRON_MAIL_SMTP_PASSWORD}
export AP_SMTP_FROM_EMAIL=${CLOUDRON_MAIL_FROM}
export AP_SMTP_SENDER_EMAIL=${CLOUDRON_MAIL_FROM}

if [ "${CLOUDRON_MAIL_SMTP_PORT}" = "465" ]; then
  export AP_SMTP_SECURE="true"
elif [ "${CLOUDRON_MAIL_SMTP_STARTTLS}" == "true" ]; then
  export AP_SMTP_SECURE="false" # For STARTTLS, secure is false
else
  export AP_SMTP_SECURE="false"
fi

# Node Environment & App Settings
export NODE_ENV="production"
export AP_EDITION="ce"
export AP_TELEMETRY_ENABLED="${AP_TELEMETRY_ENABLED:-false}" # Allow override via Cloudron env
export AP_QUEUE_MODE="REDIS"
export AP_LOG_LEVEL="${AP_LOG_LEVEL:-warn}" # Allow override
export AP_LOG_PRETTY="false"
export AP_SIGN_UP_ENABLED="${AP_SIGN_UP_ENABLED:-true}" # Allow override
export AP_SANDBOX_RUN_TIME_SECONDS="600"
export AP_EXECUTION_DATA_RETENTION_DAYS="30"
export AP_FLOW_TIMEOUT_SECONDS="600"

# Files (Local storage for 'file' piece)
export AP_LOCAL_STORE_PATH="/app/data/files"

# --- Prepare Nginx Configuration ---
export NGINX_LISTEN_PORT="8000" # Hardcoded as per CloudronManifest.json httpPort
export AP_BACKEND_INTERNAL_PORT="${AP_PORT}" # AP_PORT is already set to 3000 above

mkdir -p /run/nginx # Ensure /run/nginx directory exists if needed, though /run itself is writable
envsubst '${NGINX_LISTEN_PORT},${AP_BACKEND_INTERNAL_PORT}' < /app/code/config/nginx.conf.template > /run/nginx_app.conf
echo "Nginx configuration generated at /run/nginx_app.conf"

# --- Start Supervisord ---
echo "Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf -n
