# ActivePieces Cloudron Package - Correction Plan (002)

This document outlines corrections for issues identified during the initial build and deployment attempt.

## 1. Nginx Configuration Write Error (Read-only Filesystem)

**Issue Identified:**
The `start.sh` script attempts to write the processed Nginx configuration to `/etc/nginx/conf.d/app.conf`. In Cloudron, `/etc/` is a read-only filesystem at runtime.
Log: `/app/code/start.sh: line 132: /etc/nginx/conf.d/app.conf: Read-only file system`

**Correction:**
The Nginx configuration file must be written to a writable directory, such as `/run/`. `supervisord` will then be instructed to use this path for the Nginx configuration.

**Changes Required:**

A.  **Modify `./start.sh`:**
    Update the section for preparing Nginx configuration:
    ```diff
    # --- Prepare Nginx Configuration ---
    export NGINX_LISTEN_PORT="${CLOUDRON_HTTP_PORT}" # Cloudron always sets this
    export AP_BACKEND_INTERNAL_PORT="${AP_PORT}" # AP_PORT is already set to 3000 above
    
    echo "Templating Nginx configuration for Nginx port ${NGINX_LISTEN_PORT} and backend port ${AP_BACKEND_INTERNAL_PORT}..."
    - mkdir -p /etc/nginx/conf.d # Ensure directory exists for app.conf
    - envsubst '${NGINX_LISTEN_PORT},${AP_BACKEND_INTERNAL_PORT}' < /app/code/config/nginx.conf.template > /etc/nginx/conf.d/app.conf
    - echo "Nginx configuration generated at /etc/nginx/conf.d/app.conf"
    + mkdir -p /run/nginx # Ensure /run/nginx directory exists if needed, though /run itself is writable
    + envsubst '${NGINX_LISTEN_PORT},${AP_BACKEND_INTERNAL_PORT}' < /app/code/config/nginx.conf.template > /run/nginx_app.conf
    + echo "Nginx configuration generated at /run/nginx_app.conf"
    ```

B.  **Modify `./supervisord.conf`:**
    Update the `command` for the `[program:nginx]` section:
    ```diff
    [program:nginx]
    - command=/usr/sbin/nginx -c /etc/nginx/conf.d/app.conf -g "daemon off;"
    + command=/usr/sbin/nginx -c /run/nginx_app.conf -g "daemon off;"
    autostart=true
    # ... rest of nginx program config
    ```

## 2. TypeORM Migration Error (CLI or DataSource Not Found)

**Issue Identified:**
The `start.sh` script reports it cannot find the TypeORM CLI or the compiled data source file.
Log: `ERROR: TypeORM CLI or compiled data source for migrations not found.`
Searched paths:
*   CLI: `/app/code/backend/dist/packages/server/api/node_modules/typeorm/cli.js`
*   DataSource: `/app/code/backend/dist/packages/server/api/app/database/database-connection.js`

**Analysis:**
*   The root `activepieces_src/package.json` lists `typeorm` as a direct `"dependency"`.
*   The `server-api` build configuration (`project.json`) has `generatePackageJson: true`.
*   The Dockerfile (builder stage) runs `npm install --production --force` in `dist/packages/server/api`.
*   The Dockerfile (final stage) copies `dist/packages/server/api/node_modules` to `/app/code/backend/dist/packages/server/api/node_modules` and the compiled server code (including `app/database/database-connection.js` if built correctly) to `/app/code/backend/dist/packages/server/api/`.

Given this, `typeorm` and its CLI *should* be present. The "not found" error suggests a discrepancy between expected paths and actual paths in the final image, or an issue during the build/copy process.

**Troubleshooting and Correction Steps:**

A.  **Verify File Existence and Paths in the Built Image (User Action):**
    This is the most crucial step to pinpoint the issue. After the next `cloudron build` (once the Nginx fix above is applied, to get a runnable-enough image for inspection):
    1.  Get the image ID or tag from the `cloudron build` output.
    2.  Run a shell in the container: `docker run --rm -it <your_image_name_or_id> bash`
    3.  Inside the container, check the following paths:
        *   `ls -l /app/code/backend/dist/packages/server/api/node_modules/typeorm/cli.js` (Verify CLI exists)
        *   `ls -l /app/code/backend/dist/packages/server/api/app/database/database-connection.js` (Verify compiled data source exists)
        *   `cat /app/code/backend/dist/packages/server/api/package.json` (Inspect the generated package.json to ensure `typeorm` is listed as a dependency).
    4.  Report the findings. If files are missing or in different locations, we'll need to adjust Dockerfile `COPY` commands or the paths in `start.sh`.

B.  **Potential `start.sh` Migration Command Adjustment (If files exist but command still fails):**
    The current migration command in `start.sh` is:
    `gosu cloudron:cloudron node "${BACKEND_API_DIR}/node_modules/typeorm/cli.js" migration:run -d "${COMPILED_DATA_SOURCE_PATH}"`
    If the files are confirmed to exist at these absolute paths, this command *should* work. One minor adjustment could be to ensure the `typeorm` command is run from the `BACKEND_API_DIR` to help it resolve any relative paths it might internally use for entities, even though the data source path is absolute.
    Consider this alternative structure within `start.sh` for the migration block:
    ```bash
    # --- Database Migrations ---
    COMPILED_DATA_SOURCE_PATH_ABS="/app/code/backend/dist/packages/server/api/app/database/database-connection.js"
    # Relative path from BACKEND_API_DIR to the compiled data source
    COMPILED_DATA_SOURCE_PATH_REL="app/database/database-connection.js" 
    BACKEND_API_DIR="/app/code/backend/dist/packages/server/api"
    TYPEORM_CLI_PATH="node_modules/typeorm/cli.js" # Relative to BACKEND_API_DIR

    echo "Running database migrations..."
    if [ -f "${BACKEND_API_DIR}/${TYPEORM_CLI_PATH}" ] && [ -f "${COMPILED_DATA_SOURCE_PATH_ABS}" ]; then
        echo "Found TypeORM CLI and compiled data source."
        cd "${BACKEND_API_DIR}"
        echo "Changed directory to $(pwd) for migration."
        gosu cloudron:cloudron node "${TYPEORM_CLI_PATH}" migration:run -d "${COMPILED_DATA_SOURCE_PATH_ABS}" 
        # Or use relative: gosu cloudron:cloudron node "${TYPEORM_CLI_PATH}" migration:run -d "${COMPILED_DATA_SOURCE_PATH_REL}"
        echo "Database migrations command executed."
        cd / # Return to root
    else
        echo "ERROR: TypeORM CLI or compiled data source for migrations not found."
        echo "Searched for CLI at: ${BACKEND_API_DIR}/${TYPEORM_CLI_PATH}"
        echo "Searched for DataSource at: ${COMPILED_DATA_SOURCE_PATH_ABS}"
        # Consider exiting if migrations are critical: exit 1
    fi
    ```
    This change of directory (`cd "${BACKEND_API_DIR}"`) before running the node command is a common pattern to ensure correct module resolution and relative path handling within the executed script.

C.  **Dockerfile: Explicit `typeorm` install in builder (Fallback):**
    If, after inspection, `typeorm` is indeed missing from `dist/packages/server/api/node_modules/`, and ensuring it's a root dependency doesn't help Nx include it, a more forceful approach in the `./Dockerfile` (builder stage) would be:
    ```dockerfile
    # In builder stage, after "npm install --production --force" for server-api
    RUN cd /usr/src/app/dist/packages/server/api && npm install typeorm@0.3.18
    ```
    This would ensure `typeorm` is present in that specific `node_modules` directory before it's copied to the final stage. This is a workaround if dependency inference fails.

**Recommendation:**
1.  First, apply the Nginx configuration path fix (1.A and 1.B).
2.  Then, rebuild and deploy.
3.  If migration errors persist, perform the file verification steps (2.A).
4.  Based on findings from 2.A, we can decide if adjustments to `start.sh` migration command (2.B) or Dockerfile (2.C) are necessary.

## 3. Health Check Error (EHOSTUNREACH)

**Issue Identified:**
`Healtheck error: Error: connect EHOSTUNREACH 172.18.19.38:8000`

**Analysis:**
This is likely a consequence of the Nginx configuration error and/or the ActivePieces backend failing to start due to migration issues.

**Correction:**
Resolving items 1 and 2 above should allow Nginx and the ActivePieces application to start correctly, which should in turn resolve the health check errors.
