# ActivePieces Cloudron Build Notes

This document provides instructions for building, testing, and deploying the ActivePieces application as a custom Cloudron package.

## Prerequisites

1.  **Cloudron Account**: You need an account on a Cloudron instance with developer mode enabled.
2.  **Docker**: Docker must be installed and running on your local machine.
3.  **Cloudron CLI**: Install the Cloudron CLI tool (`cloudron`).
4.  **Git**: Git must be installed to allow the `Dockerfile` to clone the ActivePieces source code.
5.  **Icon**: An icon file named `icon.png` (ideally 256x256 or larger, PNG or SVG) must be present in the root of this packaging project (e.g., `activepices-cloudron/icon.png`).

## Package Files

Ensure the following files are in the `activepices-cloudron` directory:

*   `CloudronManifest.json` (defines the application package)
*   `Dockerfile` (builds the application image)
*   `start.sh` (runtime script for the application)
*   `nginx.conf` (Nginx configuration for Cloudron's reverse proxy)
*   `icon.png` (application icon)
*   `ActivePieces-Build-Notes.md` (this file)

## Build Process

1.  **Navigate to Project Directory**:
    Open your terminal and change to the `activepices-cloudron` directory.
    ```bash
    cd path/to/activepices-cloudron
    ```

2.  **Login to Docker Registry** (if not using Cloudron's internal registry):
    ```bash
    docker login your-registry.example.com
    ```

3.  **Build the Docker Image**:
    Run the Cloudron build command from within the `activepices-cloudron` directory:
    ```bash
    cloudron build
    ```
    This command will:
    *   Read `CloudronManifest.json`.
    *   Build the Docker image using `Dockerfile` (cloning ActivePieces version 0.63.0 by default via the `GIT_TAG` ARG in the Dockerfile).
    *   Tag and push the image to the appropriate Docker registry.

    To build a different version, modify the `GIT_TAG` argument in the `Dockerfile` or use a build argument with the Cloudron CLI:
    ```bash
    cloudron build --build-arg GIT_TAG=new-version-tag
    ```

## Deployment to Cloudron

1.  **Login to Cloudron** (if not done by `cloudron build`):
    ```bash
    cloudron login my.yourcloudron.server
    ```

2.  **Install the Application**:
    ```bash
    cloudron install --image com.activepieces.cloudronapp:0.63.0 # Adjust tag if you built a different version
    ```
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

*   **`httpPort` and `AP_PORT`**: Ensure `AP_PORT` in `start.sh` (default 3000) matches `httpPort` in `CloudronManifest.json`.

*   **Email**: Test email sending functionality (password reset, notifications).

*   **Build Commands in `Dockerfile`**: Confirm `pnpm exec nx run-many --target=build --all --parallel=1` correctly builds all necessary production artifacts for `server-api` and `ui`.

## Updating the Application

1.  **Update Source Version**:
    *   In `Dockerfile`, change the default value for the `GIT_TAG` ARG.
    *   Or, pass the new tag via build argument: `cloudron build --build-arg GIT_TAG=new.version.tag`
2.  **Manifest Version**: Update the `version` field in `CloudronManifest.json` to match the new ActivePieces version.
3.  **Rebuild**: `cloudron build` (with new tag/args if needed).
4.  **Update on Cloudron**: `cloudron update --app <appdomain> --image <new-image-tag-from-build>` (e.g., `com.activepieces.cloudronapp:new.version.tag`).
