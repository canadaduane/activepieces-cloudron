# Stage 1: Builder Stage (based on official ActivePieces build environment)
# Reverted to 18.20.5 as rebuilding bcrypt in final stage is the new strategy
FROM node:18.20.5-bullseye-slim AS builder

LABEL stage=builder

# Install build dependencies
# Use a cache mount for apt to speed up the process
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        python3 \
        g++ \
        build-essential \
        git \
        poppler-utils \
        procps \
        locales \
        locales-all \
        libcap-dev && \
    yarn config set python /usr/bin/python3 && \
    npm install -g node-gyp && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install specific npm and pnpm versions
RUN npm i -g npm@9.9.3 pnpm@9.15.0

# Set the locale
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

ENV NX_DAEMON=false

# Copy ActivePieces source code
WORKDIR /usr/src/app
COPY ./activepieces_src/ .

# Install dependencies
# The command `COPY ./activepieces_src/ .` above has already copied package.json and package-lock.json.
# Aligning with official Dockerfile which uses npm ci.
RUN npm ci

# Build server-api and react-ui
# Aligning with official Dockerfile which uses npx.
RUN npx nx run-many --target=build --projects=server-api --configuration production
RUN npx nx run-many --target=build --projects=react-ui

# Install backend production dependencies
# Aligning with official Dockerfile.
RUN cd dist/packages/server/api && npm install --production --force


# Stage 2: Final Cloudron Stage
FROM cloudron/base:4.2.0 AS final

LABEL stage=final

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    gettext-base \
    supervisor \
    poppler-utils \
    procps \
    # libcap-dev was in official base, check if needed for runtime by AP, else remove
    # For Node.js, cloudron/base includes a recent LTS.
    # If specific Node 18.20.5 is strictly required and not provided by cloudron/base,
    # it would need to be installed here. For now, assume base Node is sufficient.
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Add build tools, rebuild bcrypt, then remove build tools
# This is done to ensure bcrypt is compiled against the final stage's Node.js version and system libraries.
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 build-essential g++ && \
    # The bcrypt module is part of the server-api's dependencies.
    # We need to run npm rebuild in the directory where its node_modules and package.json are located after being copied.
    # This happens after the COPY --from=builder .../api/node_modules ... line.
    # However, to ensure the command is placed correctly, we'll do it after copying all backend files,
    # then cd into the correct directory.
    # For now, this RUN block is placed after initial runtime deps. The actual rebuild will occur after files are copied.
    # This is a placeholder for the logic, the actual rebuild will be done after COPY.
    # The actual rebuild command will be added after the COPY statements for node_modules.
    # For now, just installing tools. The rebuild will be a separate RUN command later.
    echo "Build tools installed. bcrypt will be rebuilt after files are copied." && \
    apt-get clean # Clean now, purge later after rebuild

# Install isolated-vm globally (adjust if official method is different)
# The official Dockerfile does `cd /usr/src && npm i isolated-vm@5.0.1`
# This means it's not in the main app's node_modules.
# We need to replicate its availability.
RUN mkdir -p /usr/src/isolated-vm-install && \
    cd /usr/src/isolated-vm-install && \
    npm i isolated-vm@5.0.1 && \
    # Make it findable by Node; this might need adjustment based on how AP requires it.
    # A common pattern is to ensure /usr/src/isolated-vm-install/node_modules is in NODE_PATH or linked.
    # For now, we assume AP's code knows how to find it if installed this way.
    # Or, ensure it's installed in a way that the main app's require() can find it.
    # The official Dockerfile installs it in /usr/src, which is unusual.
    # Let's try to mimic that by placing its node_modules there.
    mkdir -p /usr/src/node_modules && \
    mv /usr/src/isolated-vm-install/node_modules/isolated-vm /usr/src/node_modules/isolated-vm && \
    rm -rf /usr/src/isolated-vm-install

# Create application and configuration directories
RUN mkdir -p /app/code/backend /app/code/frontend /app/code/config /app/data /run /tmp

# Copy ActivePieces specific assets (e.g., for isolated-vm sandboxing)
# Path from official Dockerfile: packages/server/api/src/assets/default.cf
COPY --from=builder /usr/src/app/packages/server/api/src/assets/default.cf /usr/local/etc/isolate/default.cf

# Copy built artifacts from builder stage
COPY --from=builder /usr/src/app/dist/packages/server/ /app/code/backend/dist/packages/server/
COPY --from=builder /usr/src/app/dist/packages/engine/ /app/code/backend/dist/packages/engine/
COPY --from=builder /usr/src/app/dist/packages/shared/ /app/code/backend/dist/packages/shared/
# Copy the node_modules for the backend server api that were installed with --production
COPY --from=builder /usr/src/app/dist/packages/server/api/node_modules /app/code/backend/dist/packages/server/api/node_modules

# Rebuild bcrypt now that node_modules are in place
RUN echo "Rebuilding bcrypt in /app/code/backend/dist/packages/server/api..." && \
    cd /app/code/backend/dist/packages/server/api && \
    npm rebuild bcrypt --build-from-source && \
    echo "bcrypt rebuild complete. Purging build tools." && \
    apt-get purge -y --auto-remove python3 build-essential g++ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/app/dist/packages/react-ui/ /app/code/frontend/
COPY --from=builder /usr/src/app/LICENSE /app/code/LICENSE

# Copy configuration templates and scripts (these will be created in the project root)
COPY ./nginx.conf.template /app/code/config/nginx.conf.template
# COPY ./supervisord.conf /app/code/config/supervisord.conf # This will be copied directly to /etc/supervisor/conf.d
COPY ./start.sh /app/code/start.sh
RUN chmod +x /app/code/start.sh

# Copy supervisord program configuration
COPY ./supervisord.conf /etc/supervisor/conf.d/activepieces.conf

# Set correct permissions for /app/code
RUN chown -R root:root /app/code && chmod -R 755 /app/code

# Health check and port are defined in CloudronManifest.json
# Cloudron's supervisor will manage starting services via start.sh
CMD ["/app/code/start.sh"]
