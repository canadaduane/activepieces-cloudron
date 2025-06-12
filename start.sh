

<file_content>
#!/bin/bash

set -eo pipefail # Exit on error, treat unset variables as an error, and propagate exit status through pipes

echo "Starting ActivePieces..."

# Create necessary directories if they don't exist
mkdir -p /app/data/cache /app/data/logs /app/data/configs /app/data/encryption /app/data/files
mkdir -p /tmp
mkdir -p /run

# Set ownership to the cloudron user
chown -R cloudron:cloudron /app/data /tmp /run

# --- Configuration based on Cloudron Environment Variables ---

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
# AP_REDIS_USER and AP_REDIS_DB are also available in .env.example, defaults are usually fine.

# Application URLs & Ports
export AP_BASE_URL="https://${CLOUDRON_APP_DOMAIN}"
export AP_FRONTEND_URL="${AP_BASE_URL}"
export AP_WEBHOOK_URL="${AP_BASE_URL}/api/v1/webhooks" # Default from docs, should be fine
export AP_PORT="3000" # Internal port the Node.js app listens on

# JWT Secret & Encryption Key
JWT_SECRET_FILE="/app/data/jwt_secret.txt"
if [ ! -f "${JWT_SECRET_FILE}" ]; then
    echo "Generating new AP_JWT_SECRET..."
    openssl rand -hex 32 > "${JWT_SECRET_FILE}" # 32 bytes = 64 hex chars
    chmod 600 "${JWT_SECRET_FILE}"
fi
export AP_JWT_SECRET=$(cat "${JWT_SECRET_FILE}")

ENCRYPTION_KEY_FILE="/app/data/encryption/encryption_key.txt"
if [ ! -f "${ENCRYPTION_KEY_FILE}" ]; then
    echo "Generating new AP_ENCRYPTION_KEY..."
    openssl rand -hex 32 > "${ENCRYPTION_KEY_FILE}" # As per AP docs (32 hex chars for AES-128, or 64 for AES-256. Their example is 32 hex chars)
    chmod 600 "${ENCRYPTION_KEY_FILE}"
fi
export AP_ENCRYPTION_KEY=$(cat "${ENCRYPTION_KEY_FILE}")

# Email (Sendmail Addon)
export AP_SMTP_HOST=${CLOUDRON_MAIL_SMTP_SERVER}
export AP_SMTP_PORT=${CLOUDRON_MAIL_SMTP_PORT}
export AP_SMTP_USERNAME=${CLOUDRON_MAIL_SMTP_USERNAME}
export AP_SMTP_PASSWORD=${CLOUDRON_MAIL_SMTP_PASSWORD}
export AP_SMTP_FROM_EMAIL=${CLOUDRON_MAIL_FROM}
export AP_SMTP_SENDER_EMAIL=${CLOUDRON_MAIL_FROM} # Alias from their .env.example

if [ "${CLOUDRON_MAIL_SMTP_PORT}" = "465" ]; then
  export AP_SMTP_SECURE="true"
elif [ "${CLOUDRON_MAIL_SMTP_STARTTLS}" == "true" ]; then
  export AP_SMTP_SECURE="false" # For STARTTLS, secure is false, library should handle upgrade
  # ActivePieces might need an explicit STARTTLS flag if its mailer supports it e.g. AP_SMTP_REQUIRE_TLS=true
else
  export AP_SMTP_SECURE="false"
fi

# Node Environment & App Settings
export NODE_ENV="production"
export AP_EDITION="ce" # Community Edition
export AP_TELEMETRY_ENABLED="false"
export AP_QUEUE_MODE="REDIS"
export AP_LOG_LEVEL="warn" # Default INFO, 'warn' for less verbosity in production
export AP_LOG_PRETTY="false"
export AP_SIGN_UP_ENABLED="true"
export AP_SANDBOX_RUN_TIME_SECONDS="600"
export AP_EXECUTION_DATA_RETENTION_DAYS="30"
export AP_FLOW_TIMEOUT_SECONDS="600"

# Files (Local storage for 'file' piece, if used)
export AP_LOCAL_STORE_PATH="/app/data/files"

# Database Migrations
echo "Running database migrations..."
cd /app/code
# The TypeORM CLI needs the compiled data source file.
# Path needs to be verified after build: /app/code/dist/packages/server/api/app/database/database-connection.js
COMPILED_DATA_SOURCE_PATH="/app/code/dist/packages/server/api/app/database/database-connection.js"

if [ -f "${COMPILED_DATA_SOURCE_PATH}" ]; then
    echo "Found compiled data source at ${COMPILED_DATA_SOURCE_PATH}"
    if node ./node_modules/typeorm/cli.js migration:run -d "${COMPILED_DATA_SOURCE_PATH}"; then
        echo "Database migrations command executed successfully."
    else
        echo "Database migrations command failed. Check logs for details."
        # exit 1 # Optionally exit if migrations are critical and fail
    fi
else
    echo "ERROR: Compiled data source for migrations not found at ${COMPILED_DATA_SOURCE_PATH}. Cannot run migrations."
    # exit 1 # Migrations are likely critical
fi

echo "Starting ActivePieces Node.js backend on port ${AP_PORT}..."
exec /usr/bin/node --enable-source-maps /app/code/dist/packages/server/api/main.js
</file_content>
