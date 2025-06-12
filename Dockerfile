# Stage 1: Builder Stage - Now using cloudron/base for consistency
FROM cloudron/base:4.2.0 AS builder

LABEL stage=builder

# Install build dependencies
# cloudron/base:4.2.0 includes Node.js 18.18.0.
# We need to ensure other build tools are present.
RUN apt-get update && \
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
        libcap-dev \
    && npm install -g node-gyp \
    && apt-get clean && \
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
# This will compile bcrypt and other native dependencies using Node 18.18.0 from cloudron/base.
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
    && apt-mark manual nginx gettext-base supervisor poppler-utils procps \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/app/dist/packages/server/api /app/code/backend/dist/packages/server/api
COPY --from=builder /usr/src/app/dist/packages/react-ui /app/code/frontend/
COPY --from=builder /usr/src/app/LICENSE /app/code/LICENSE

# Copy configuration templates and scripts (these will be created in the project root)
COPY ./nginx.conf.template /app/code/config/nginx.conf.template
COPY ./start.sh /app/code/start.sh
RUN chmod +x /app/code/start.sh

# Copy supervisord program configuration
COPY ./supervisord.conf /etc/supervisor/conf.d/activepieces.conf

# Set correct permissions for /app/code
RUN chown -R root:root /app/code && chmod -R 755 /app/code

# Health check and port are defined in CloudronManifest.json
# Cloudron's supervisor will manage starting services via start.sh
CMD ["/app/code/start.sh"]
