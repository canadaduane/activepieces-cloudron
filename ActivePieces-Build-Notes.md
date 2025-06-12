# ActivePieces Cloudron Build Notes

This document provides instructions for building, testing, and deploying the ActivePieces application as a custom Cloudron package.

## Prerequisites

1.  **Cloudron Account**: You need an account on a Cloudron instance with developer mode enabled.
2.  **Docker**: Docker must be installed and running on your local machine.
3.  **Cloudron CLI**: Install the Cloudron CLI tool (`cloudron`).
4.  **ActivePieces Source Code**: The source code for ActivePieces should be present in the `./activepieces_src/` subdirectory of this project. The `./Dockerfile` copies from this location.
5.  **Icon**: An icon file named `logo.png` (ideally 256x256 or larger, PNG or SVG) must be present in the root of this packaging project. (Note: `CloudronManifest.json` refers to `file://icon.png`, ensure `logo.png` is renamed to `icon.png` or the manifest is updated).

## Package Files

Ensure the following files are in the `activepieces-cloudron` project directory:

*   `CloudronManifest.json` (defines the application package)
*   `Dockerfile` (builds the application image using `./activepieces_src/`)
*   `start.sh` (runtime script for the application, launches supervisord)
*   `nginx.conf.template` (Nginx configuration template)
*   `supervisord.conf` (Supervisord configuration to manage Nginx and ActivePieces app)
*   `icon.png` (application icon, ensure this matches the manifest)
*   `ActivePieces-Build-Notes.md` (this file)
*   `./activepieces_src/` (directory containing the ActivePieces source code)

## Build Process

1.  **Navigate to Project Directory**:
    Open your terminal and change to the `activepieces-cloudron` directory.
    ```bash
    cd path/to/activepieces-cloudron
    ```

2.  **Ensure ActivePieces Source**:
    Make sure the `./activepieces_src/` directory contains the version of ActivePieces you intend to package.

3.  **Login to Docker Registry** (if not using Cloudron's internal registry or a pre-configured one):
    ```bash
    docker login your-registry.example.com
    ```

4.  **Build the Docker Image**:
    Run the Cloudron build command from within the `activepieces-cloudron` directory:
    ```bash
    cloudron build
    ```
    This command will:
    *   Read `CloudronManifest.json`.
    *   Build the Docker image using `Dockerfile`, which uses the content of `./activepieces_src/`.
    *   Tag and push the image to the appropriate Docker registry (e.g., `yourdockerhubuser/com.activepieces.cloudronapp:0.63.0-cloudron1` based on manifest fields).

    To build a specific version of ActivePieces, you must update the contents of the `./activepieces_src/` directory to that version's source code, and update `upstreamVersion` and `version` in `CloudronManifest.json` accordingly before running `cloudron build`.

## Deployment to Cloudron

1.  **Login to Cloudron** (if not already done, or if `cloudron build` didn't handle it):
    ```bash
    cloudron login my.yourcloudron.server
    ```

2.  **Install the Application**:
    Use the image name and tag that `cloudron build` outputs. For example, if your manifest `id` is `com.activepieces.cloudronapp` and `version` is `0.63.0-cloudron1`, and your Docker Hub username (if used) is `youruser`:
    ```bash
    cloudron install --image youruser/com.activepieces.cloudronapp:0.63.0-cloudron1
    ```
    If using Cloudron's local registry (default for `cloudron build` without specifying a repo), the image name might be simpler, like `com.activepieces.cloudronapp:0.63.0-cloudron1`. Pay attention to the output of `cloudron build`.
    The CLI will prompt for a location (e.g., `activepieces.yourcloudron.server`).

## Testing

1.  **Access the Application**: Open the URL provided after installation.
2.  **Initial Setup**: Create an admin account as prompted by ActivePieces.
3.  **Core Functionality**: Test user registration, login, flow creation, execution, database saves, and Redis queue functionality.
4.  **Check Logs**: `cloudron logs -f --app activepieces.yourcloudron.server`
5.  **Resource Usage**: Monitor in Cloudron dashboard. Adjust `memoryLimit` in `CloudronManifest.json` if needed.

## Important Verification Points (Post-Build & During Testing)

*   **Database Migrations (`start.sh`)**:
    *   **CRITICAL**: Verify the path to the compiled TypeORM data source used in the migration command: `COMPILED_DATA_SOURCE_PATH="/app/code/dist/packages/server/api/app/database/database-connection.js"` in `start.sh`.
    *   After the first `cloudron build`, inspect the Docker image (or the `dist` output of the builder stage if you build locally) to confirm this path is correct. It depends on the TypeScript `outDir` in `packages/server/api/tsconfig.json` and how `nx` structures the output for the `server-api` package.
    *   Ensure the `node ./node_modules/typeorm/cli.js migration:run -d "${COMPILED_DATA_SOURCE_PATH}"` command executes successfully. Check application logs for messages about migrations.

*   **Environment Variables (`start.sh`)**:
    *   Thoroughly review all `AP_` environment variables in `start.sh`.
    *   Compare them against the official ActivePieces documentation: `https://www.activepieces.com/docs/install/configuration/environment-variables` and the `.env.example` file from the version of ActivePieces you are packaging.
    *   Ensure mappings from `CLOUDRON_*` variables are correct, especially for PostgreSQL SSL (`AP_POSTGRES_SSL_ENABLED`) and SMTP settings (`AP_SMTP_SECURE` and related flags).

*   **Frontend Asset Path (`Dockerfile` and `nginx.conf`)**:
    *   **CRITICAL**: Verify the path `dist/packages/ui` used in `Dockerfile` (for `COPY --from=builder ... /app/code/dist/packages/ui`) and in `nginx.conf` (for `root /app/code/dist/packages/ui;`).
    *   The `nx build ui` (or similar command used by `nx run-many --target=build`) determines this output path. Inspect the build output to confirm. The package name for the frontend is `ui` in the `nx.json` and `packages/` directory, so `dist/packages/ui` is the likely output.

*   **Backend Entry Point (`start.sh`)**:
    *   Verify the path to the main backend script: `exec /usr/bin/node --enable-source-maps /app/code/dist/packages/server/api/main.js`. This should be correct if the `server-api` package builds as expected.

*   **`httpPort` and `AP_PORT`**:
    *   `CloudronManifest.json:httpPort` (e.g., 8000) is the port Nginx (inside the container) listens on. This is what Cloudron's external proxy connects to.
    *   `AP_PORT` in `start.sh` (e.g., 3000) is the internal port the ActivePieces Node.js backend listens on.
    *   Nginx (listening on `httpPort`) proxies requests to the Node.js backend on `AP_PORT`. These two ports should be different.

*   **Email**: Test email sending functionality (password reset, notifications).
*   **Nginx and Supervisord**: Verify both Nginx and the ActivePieces Node.js app are running correctly via `supervisorctl status` (if available in `cloudron exec`) or by checking logs.

*   **Build Commands in `Dockerfile`**: Confirm `pnpm exec nx run-many --target=build --all --parallel=1` correctly builds all necessary production artifacts for `server-api` and `ui`.

## Updating the Application

1.  **Update Source Version**:
    *   Replace the contents of the `./activepieces_src/` directory with the source code of the new ActivePieces version.
2.  **Manifest Version**:
    *   Update `upstreamVersion` in `CloudronManifest.json` to the new ActivePieces version (e.g., "0.64.0").
    *   Update `version` in `CloudronManifest.json` for the package itself (e.g., "0.64.0-cloudron1").
3.  **Rebuild**:
    ```bash
    cloudron build
    ```
4.  **Update on Cloudron**:
    Use the new image tag output by `cloudron build`.
    ```bash
    cloudron update --app <app.domain> --image <yourdockeruser/com.activepieces.cloudronapp:new-package-version>
    ```
    Example: `cloudron update --app activepieces.yourcloudron.server --image yourdockeruser/com.activepieces.cloudronapp:0.64.0-cloudron1`
