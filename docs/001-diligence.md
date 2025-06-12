# ActivePieces Cloudron Packaging Diligence (./docs/001-diligence.md)

This document outlines the steps to review, fix, and improve the Cloudron packaging for ActivePieces.

## I. CloudronManifest.json Review & Updates

**Objective**: Ensure `CloudronManifest.json` is correct, complete, and follows best practices.

**Current Manifest Issues/Areas for Improvement:**

1.  **`author`**:
    *   **Current**: `"Cloudron Packaging Team"`
    *   **Recommendation**: Change to the actual packager or ActivePieces team if this is a community/self-hosted package. If intended for the official Cloudron store, this might be adjusted by the Cloudron team later. For now, assume self-packaging.
    *   **Action**: Update `author` field.

2.  **`version` vs. `upstreamVersion`**:
    *   **Current `version`**: `"0.63.0"`
    *   **Recommendation**: Add an `upstreamVersion` field to track the specific version of ActivePieces being packaged. The `version` field should then represent the package version itself (e.g., `0.63.0-cloudron1`).
    *   **Action**: Add `upstreamVersion` and adjust `version` accordingly.

3.  **`memoryLimit`**:
    *   **Current**: `1024` (interpreted as MB)
    *   **Recommendation**: Specify in bytes for clarity as per manifest guide (e.g., `1073741824` for 1GB). Verify if 1GB is an appropriate default or if it can be lower/needs to be higher based on ActivePieces' requirements.
    *   **Action**: Update `memoryLimit` to bytes and verify requirement.

4.  **`icon`**:
    *   **Current**: `"icon.png"`
    *   **Recommendation**: Prefix with `file://` as per manifest guide: `"file://icon.png"`.
    *   **Action**: Update `icon` field.

5.  **`proxyPaths` field**:
    *   **Current**: Contains `"/api"` and `"/socket.io"` entries.
    *   **Recommendation**: This field is not standard in the provided Cloudron manifest documentation. Proxying logic is typically handled by a web server (like Nginx) within the container, configured to listen on `httpPort`. Cloudron's main reverse proxy forwards all traffic to `httpPort`.
    *   **Action**:
        *   Investigate if ActivePieces requires a separate web server (e.g., Nginx) in the Docker image to handle these paths and websockets.
        *   If so, remove `proxyPaths` from the manifest and implement this logic in the Dockerfile (e.g., Nginx config).
        *   If ActivePieces itself (Node.js app on port 3000) handles these paths directly, this field might be a legacy or custom Cloudron feature. Verify its necessity and standard compliance. For websockets, Cloudron's main proxy handles `Upgrade` headers automatically if the app supports it on its `httpPort`.

6.  **`spa` field**:
    *   **Current**: Contains `path` and `index` for SPA.
    *   **Recommendation**: Similar to `proxyPaths`, this is not a standard manifest field. SPA routing (serving `index.html` for client-side routes) is typically configured in the web server (e.g., Nginx `try_files`) within the container.
    *   **Action**:
        *   If a web server like Nginx is used, remove this field and configure SPA routing in the Nginx config.
        *   If ActivePieces serves its own frontend and handles SPA routing, verify if this field is truly needed or if the app can manage without it.

**Add Missing/Optional Manifest Fields:**

7.  **`upstreamVersion`**:
    *   **Action**: Add this field to specify the version of ActivePieces being packaged (e.g., `"0.63.0"`).

8.  **`tags`**:
    *   **Recommendation**: Add relevant tags for discoverability in the Cloudron store (even for custom apps, it's good practice).
    *   **Action**: Add tags like `["automation", "no-code", "workflow", "integration"]`.

9.  **Single Sign-On (SSO)**:
    *   **Recommendation**: Investigate ActivePieces' support for OIDC or LDAP. Integrating with Cloudron SSO (`oidc` addon) is highly recommended.
    *   **Action**:
        *   Check ActivePieces documentation for OIDC/LDAP capabilities.
        *   If supported, add the `oidc` addon to the manifest and configure necessary environment variables (e.g., `CLOUDRON_OIDC_CLIENT_ID`, etc.) in `start.sh`.
        *   Update `postInstallMessage` regarding SSO.
        *   Consider `optionalSso: true` if SSO is not mandatory.

10. **`documentationUrl`**:
    *   **Action**: Add a link to ActivePieces' official documentation.

11. **`forumUrl`**:
    *   **Action**: Add a link to ActivePieces' community forum or support page.

12. **`changelog`**:
    *   **Action**: Add a brief changelog for the package version or link to `file://CHANGELOG.md`.

13. **`configurePath`**:
    *   **Action**: If ActivePieces has a specific admin or initial setup page, add its path here (e.g., `"/setup"` or `"/admin"`).

14. **`logPaths`**:
    *   **Action**: If ActivePieces or its components write logs to specific files instead of `stdout`/`stderr`, list them here so Cloudron can manage them. (e.g. `["/app/data/logs/app.log"]`). Prefer `stdout/stderr`.

**Verify Existing Fields:**

15. **`healthCheckPath`**:
    *   **Current**: `"/api/v1/flags"`
    *   **Action**: Confirm this path returns a `2xx` status code when ActivePieces is running correctly and is lightweight.

**Important Clarification for Manifest & Nginx:**

16. **`httpPort` and Internal Port Handling**:
    *   **Observation**: Current manifest `httpPort` is `3000`. Nginx in our plan will proxy to an internal backend port (also potentially 3000).
    *   **Action**:
        *   The `httpPort` in `CloudronManifest.json` (e.g., `8000`) should be the port Nginx listens on (set via `CLOUDRON_HTTP_PORT` in `start.sh`).
        *   The ActivePieces Node.js backend should listen on a *different* internal port (e.g., `3001`, or keep it `3000` if Nginx listens on `8000`).
        *   Update `nginx.conf.template` `listen` directive and `proxy_pass` target port accordingly.
        *   Ensure `start.sh` correctly sets these ports for Nginx and potentially for the Node.js app if its listening port is configurable.

## II. Dockerfile Plan (`./Dockerfile`)

**Objective**: Create a multi-stage Dockerfile for Cloudron that builds ActivePieces and sets up a runtime environment with Nginx and Supervisor.

**Structure & Content Plan:**

1.  **`builder` Stage (based on `node:18.20.5-bullseye-slim`):**
    *   **Action**: Install build dependencies from official `activepieces_src/Dockerfile` (e.g., `openssh-client`, `python3`, `g++`, `build-essential`, `git`, `poppler-utils`, `procps`, `locales`, `libcap-dev`).
    *   **Action**: Install specific `npm` and `pnpm` versions as per official Dockerfile.
    *   **Action**: Set locales (`LANG`, `LANGUAGE`, `LC_ALL`).
    *   **Action**: Copy the entire `activepieces_src` project content.
    *   **Action**: `WORKDIR /usr/src/app` (or similar, matching official build context).
    *   **Action**: Run `npm ci` to install dependencies based on `package-lock.json`.
    *   **Action**: Run `npx nx run-many --target=build --projects=server-api --configuration production`.
    *   **Action**: Run `npx nx run-many --target=build --projects=react-ui`.
    *   **Action**: `RUN cd dist/packages/server/api && npm install --production --force` to install backend production dependencies.

2.  **Final Cloudron Stage (based on `cloudron/base:4.2.0` or newer):**
    *   **Action**: Install runtime dependencies: `nginx`, `gettext-base` (for `envsubst`), `supervisor`, `poppler-utils`, `procps`, `libcap-dev`.
        *   Verify if `cloudron/base` provides a compatible Node.js version (18.20.5). If not, plan to install Node.js 18.20.5.
    *   **Action**: Install `isolated-vm@5.0.1` globally (e.g., `RUN cd /tmp && npm i isolated-vm@5.0.1 && mkdir -p /usr/src/node_modules && mv /tmp/node_modules/isolated-vm /usr/src/node_modules/isolated-vm`).
    *   **Action**: `RUN mkdir -p /app/code/backend /app/code/frontend /app/code/config /app/data /run /tmp`.
    *   **Action**: Copy `activepieces_src/packages/server/api/src/assets/default.cf` to `/usr/local/etc/isolate/default.cf`.
    *   **Action**: Copy built artifacts from `builder` stage:
        *   Backend (`dist/packages/server`, `dist/packages/engine`, `dist/packages/shared`) to `/app/code/backend/`.
        *   Frontend (`dist/packages/react-ui`) to `/app/code/frontend/`.
        *   `LICENSE` file to `/app/code/LICENSE`.
    *   **Action**: Copy configuration templates and scripts:
        *   `nginx.conf.template` (to be created) to `/app/code/config/nginx.conf.template`.
        *   `supervisord.conf` (to be created) to `/app/code/config/supervisord.conf`.
        *   `start.sh` (to be created for Cloudron) to `/app/code/start.sh`.
    *   **Action**: `RUN chmod +x /app/code/start.sh`.
    *   **Action**: Set `CMD ["/app/code/start.sh"]`.

## III. Nginx Configuration Plan (`./nginx.conf.template`)

**Objective**: Adapt `activepieces_src/nginx.react.conf` for Cloudron, making it templatable for `start.sh`.

**Content Plan (based on `activepieces_src/nginx.react.conf`):**
```nginx
events{} # May not be needed if Cloudron's base Nginx config handles it.
http {
    include /etc/nginx/mime.types;
    client_max_body_size 100m; # Keep or adjust as needed.

    server_tokens off; # Good practice.

    # Security headers - keep these.
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Redirect HTTP to HTTPS (Cloudron handles this at its edge proxy, but good for direct access if ever possible)
    # Not strictly needed if only accessed via Cloudron proxy.

    # Log to stdout/stderr for Cloudron
    access_log /dev/stdout;
    error_log /dev/stderr warn;

    server {
        listen ${NGINX_LISTEN_PORT}; # Placeholder for CLOUDRON_HTTP_PORT
        server_name localhost; # Cloudron handles actual domain mapping.

        root /app/code/frontend; # Adjusted path for frontend static files
        index index.html;

        error_page 404 /404.html;
        location = /404.html {
            root /app/code/frontend; # Adjusted path
            try_files $uri $uri/ /index.html;
        }

        location /socket.io {
            proxy_pass http://127.0.0.1:${AP_BACKEND_INTERNAL_PORT}/socket.io; # Placeholder for backend port
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $host;
            proxy_read_timeout 900s;
            proxy_send_timeout 900s;
        }

        # Serve static assets with caching headers
        location ~* ^/(?!api/).*.(css|js|jpg|jpeg|png|gif|ico|svg)$ {
            root /app/code/frontend; # Adjusted path
            add_header Expires "0"; # Consider if this is correct, or if immutable is better
            add_header Cache-Control "public, max-age=31536000, immutable"; # Good for versioned assets
        }

        # SPA routing for frontend
        location / {
           root /app/code/frontend; # Adjusted path
           try_files $uri $uri/ /index.html?$args;
        }

        # API proxy
        location /api/ {
            proxy_pass http://127.0.0.1:${AP_BACKEND_INTERNAL_PORT}/; # Placeholder for backend port
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $host;
            proxy_read_timeout 900s;
            proxy_send_timeout 900s;

            # SSE specific settings
            proxy_buffering off;
            proxy_cache off;
        }
    }
}
```
*   **Action**: Create this file as `./nginx.conf.template` in the project root.
*   Placeholders `${NGINX_LISTEN_PORT}` and `${AP_BACKEND_INTERNAL_PORT}` will be substituted by `envsubst` in `start.sh`.

## IV. Supervisord Configuration Plan (`./supervisord.conf`)

**Objective**: Create a `supervisord.conf` to manage Nginx and the ActivePieces backend Node.js application.

**Content Plan:**
```ini
[supervisord]
nodaemon=true
logfile=/dev/null ; Process logs will go to their own stdout/stderr
pidfile=/run/supervisord.pid
childlogdir=/tmp ; Or /dev/null if not needed

[program:nginx]
command=/usr/sbin/nginx -c /etc/nginx/conf.d/app.conf -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
user=root ; Nginx master process typically runs as root, workers as www-data or nginx

[program:activepieces]
command=gosu cloudron:cloudron node --enable-source-maps /app/code/backend/dist/packages/server/api/main.js
directory=/app/code/backend/dist/packages/server/api/ ; Set working directory
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
user=root ; gosu handles the drop to 'cloudron' user
environment=NODE_ENV="production" ; Add other necessary runtime env vars if any, or ensure start.sh exports them
```
*   **Action**: Create this file as `./supervisord.conf` in the project root.
*   The Nginx command assumes its config will be at `/etc/nginx/conf.d/app.conf` after `envsubst`.

## V. Cloudron `start.sh` Script Plan (`./start.sh`)

**Objective**: Create the main entrypoint script for the Cloudron container, integrating logic from the existing `start.sh` and launching services via `supervisord`.

**Key Integration Points from Existing `./start.sh`:**

*   **Action**: Preserve the `set -eo pipefail` and initial `echo`.
*   **Action**: Preserve directory creation: `mkdir -p /app/data/cache ... /run`.
*   **Action**: Preserve `chown -R cloudron:cloudron /app/data /tmp /run`.
*   **Action**: **Crucially, integrate all `AP_` environment variable configurations** based on `CLOUDRON_` variables (PostgreSQL, Redis, SMTP, App URLs).
    *   This includes logic for `AP_POSTGRES_SSL_ENABLED`, Redis URL construction, and SMTP security flags.
*   **Action**: **Integrate JWT and Encryption Key generation logic**:
    *   Check for `/app/data/jwt_secret.txt` and `/app/data/encryption/encryption_key.txt`.
    *   Generate them using `openssl rand -hex 32` if they don't exist.
    *   Export `AP_JWT_SECRET` and `AP_ENCRYPTION_KEY` from these files.
*   **Action**: Preserve other `AP_` runtime configurations (NODE_ENV, edition, telemetry, queue mode, log settings, etc.).
*   **Action**: Preserve `AP_LOCAL_STORE_PATH="/app/data/files"`.

**Database Migrations (to be run *before* starting supervisord):**

*   **Action**: Integrate the database migration section from the existing `start.sh`.
    *   The command is `node ./node_modules/typeorm/cli.js migration:run -d "${COMPILED_DATA_SOURCE_PATH}"`.
    *   **Path Verification**:
        *   The `COMPILED_DATA_SOURCE_PATH` (currently `/app/code/dist/packages/server/api/app/database/database-connection.js` in existing script) must be updated to reflect the location of the built backend in our new Dockerfile structure (e.g., `/app/code/backend/dist/packages/server/api/app/database/database-connection.js`).
        *   The `node_modules/typeorm` must be accessible. This implies migrations should be run from a directory where `node_modules` (containing `typeorm`) is a subdirectory or accessible in the Node.js module resolution path. For example, `cd /app/code/backend/dist/packages/server/api/ && node ../../../../../node_modules/typeorm/cli.js migration:run ...` if `node_modules` is at `/app/code/backend/node_modules`. Or, if `typeorm` is a dependency of `server-api` itself, it might be `cd /app/code/backend/dist/packages/server/api/ && node node_modules/typeorm/cli.js migration:run ...`. This needs careful pathing. A common practice is to have a script in `package.json` for migrations that TypeORM CLI can use, which resolves paths correctly.
    *   Consider making migration failure an explicit exit: `exit 1` if migrations are critical.

**New Logic for Supervisord and Nginx:**

*   **Action**: Add Nginx configuration templating using `envsubst`:
    *   `export NGINX_LISTEN_PORT="${CLOUDRON_HTTP_PORT:-8000}"`
    *   `export AP_BACKEND_INTERNAL_PORT="${AP_INTERNAL_PORT:-3000}"` (Confirm `AP_INTERNAL_PORT` is the env var ActivePieces uses for its listening port, or set `AP_PORT` as in existing script).
    *   `envsubst '${NGINX_LISTEN_PORT},${AP_BACKEND_INTERNAL_PORT}' < /app/code/config/nginx.conf.template > /etc/nginx/conf.d/app.conf`.
*   **Action**: Copy `supervisord.conf`: `cp /app/code/config/supervisord.conf /etc/supervisor/conf.d/activepieces.conf`.
*   **Action**: The final command will be `exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf -n`.

**Overall Structure of New `./start.sh`:**
1.  Shebang, `set -eo pipefail`.
2.  Initial echos, directory creation, chown.
3.  All `AP_` environment variable exports from existing script (DB, Redis, URLs, SMTP, runtime settings).
4.  JWT & Encryption Key generation/loading.
5.  Database migration execution (with corrected paths).
6.  Nginx config templating.
7.  Supervisord config copy.
8.  `exec supervisord`.

*   **Action**: Create this new `./start.sh` in the project root, incorporating the above.

## VI. Review Existing Build Notes
*   The `AP_INTERNAL_PORT` (or `AP_PORT`) environment variable for the Node.js app's listening port should be consistently used. The existing `start.sh` sets `AP_PORT="3000"`. This should be used as the target for Nginx's `proxy_pass`.

## VI. Review Existing Build Notes

*   **Action**: Review the existing `ActivePieces-Build-Notes.md` file to ensure alignment with Cloudron CLI best practices and our packaging plan.

## VII. General Best Practices & Other Checks

1.  **Read-only vs. Writable Directories**:
    *   **Action**: Double-check that only `/app/data`, `/tmp`, and `/run` are treated as writable by the application.

2.  **Security of Sensitive Information**:
    *   **Action**: Ensure database credentials, API keys, etc., are passed via environment variables or generated and stored securely in `/app/data`.

3.  **Updates**:
    *   **Action**: Consider how the application handles updates. Database migrations in `start.sh` are key.

4.  **Health Checks**:
    *   **Action**: Re-verify `healthCheckPath` is robust.

5.  **Multi-process Management**:
    *   **Action**: If ActivePieces involves multiple processes, check if `supervisor` or `pm2` is used or needed. The current setup seems to be a single Node.js application.

6.  **Resource Limits**:
    *   **Action**: Review memory usage and adjust `memoryLimit` if necessary. Consider if the app can dynamically adapt to memory limits (e.g., for worker counts).

7.  **Cloudron CLI Usage**:
    *   **Action**: Review `ActivePieces-Build-Notes.md` (or create it) to ensure build, push, install, and update instructions using `cloudron build` and `cloudron update --app <app.domain>` (or `cloudron install`) are clear.

## VI. Build and Test

1.  **Build the image**: `docker build -t yourusername/activepieces-cloudron:test .` (or use `cloudron build`).
2.  **Install on a test Cloudron**: `cloudron install --image yourusername/activepieces-cloudron:test`.
3.  **Test Functionality**:
    *   Initial setup.
    *   Core features of ActivePieces.
    *   SSO (if implemented).
    *   Email sending (if `sendmail` addon is used for features).
4.  **Check Logs**: `cloudron logs --app <app.domain> -f`.
5.  **Test Updates**: Push a new version and run `cloudron update --app <app.domain> --image yourusername/activepieces-cloudron:newtest`.
6.  **Test Backup/Restore**.

This scratchpad will serve as a checklist for improving the ActivePieces Cloudron package.
