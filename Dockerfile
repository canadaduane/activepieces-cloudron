# Stage 1: Builder
# Use an official Node.js image that matches ActivePieces' requirements
FROM node:18.20.5-bullseye-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pnpm \
    git \
    python3 \
    g++ \
    make \
    build-essential \
    poppler-utils \
    # libcap-dev is for building, runtime needs libcap2-bin
    # locales are good to have configured early
    && rm -rf /var/lib/apt/lists/*

# Configure pnpm to use a shared cache directory to speed up subsequent builds
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN pnpm config set store-dir /pnpm-store

WORKDIR /build_src

# Copy ActivePieces source code
# Ensure 'activepieces_src' contains the correct version of the code
COPY activepieces_src/. /build_src/

# Install dependencies using pnpm
# Using --frozen-lockfile if pnpm-lock.yaml is present and committed
# Their Dockerfile uses `npm ci --force-empty-lockfile` which suggests issues with lockfiles sometimes.
# For pnpm, `pnpm install --frozen-lockfile` is strict. If no lockfile, just `pnpm install`.
# The cloned source should have a lockfile.
RUN pnpm install --frozen-lockfile

# Build the application
# Their Dockerfile uses: npx nx run-many --target=build --all --parallel=1
# We adapt this for pnpm if nx is listed as a devDependency
RUN pnpm exec nx run-many --target=build --all --parallel=1

# Prune dev dependencies from node_modules to prepare for production
RUN pnpm prune --prod


# Stage 2: Final image using Cloudron base
FROM cloudron/base:4.2.0

# Install runtime dependencies
# cloudron/base:4.2.0 includes Node.js 18.18.2, which should be compatible.
# It also includes locales, python3.
# We need poppler-utils for runtime, and libcap2-bin (runtime for libcap-dev).
# gettext-base for envsubst if start.sh needs it.
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    libcap2-bin \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Set up application directories
# /app/code is read-only for the app, /app/data is writable and backed up
# /tmp and /run are for temporary/runtime files
RUN mkdir -p /app/code /app/data /run /tmp
WORKDIR /app/code

# Copy essential files from the builder stage
COPY --from=builder /build_src/package.json /app/code/package.json
COPY --from=builder /build_src/pnpm-lock.yaml /app/code/pnpm-lock.yaml
# Copy any other root-level config files needed for runtime if any (e.g., .env.production if used differently)

# Copy built application artifacts
# Verify these paths from the actual build output of ActivePieces
COPY --from=builder /build_src/dist/packages/server/api /app/code/dist/packages/server/api
COPY --from=builder /build_src/dist/packages/ui /app/code/dist/packages/ui
# The original Nginx conf served from /usr/share/nginx/html which contained contents of packages/ui/dist
# So, the path might be /build_src/packages/ui/dist. Let's assume the build output of `nx build ui` goes to `dist/packages/ui`

# Copy production node_modules
COPY --from=builder /build_src/node_modules /app/code/node_modules

# Copy our start script. nginx.conf is handled by Cloudron manifest.
COPY start.sh /app/code/start.sh
RUN chmod +x /app/code/start.sh

# Ensure /app/data, /tmp, /run are writable by the cloudron user
# The cloudron user (uid 999, gid 999) is already created in the base image.
RUN chown -R cloudron:cloudron /app/data /tmp /run && \
    # /app/code should be owned by cloudron for consistency, though it's mostly read-only at runtime
    chown -R cloudron:cloudron /app/code

# Switch to the cloudron user
USER cloudron

# Set the command to run when the container starts
CMD ["/app/code/start.sh"]
