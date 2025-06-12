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
*   `activepieces_src/` (This directory will be created by the `git clone` command in the `Dockerfile`'s builder stage, but was also created by a previous `terminal` command. It's good practice to `.gitignore` this directory if you commit the packaging files to version control, as it's a build artifact).

## Build Process

1.  **Navigate to Project Directory**:
    Open your terminal and change to the `activepices-cloudron` directory.
    ```bash
    cd path/to/activepices-cloudron
    ```

2.  **Login to Docker Registry**:
    If you are using a private Docker registry, log in:
    ```bash
    docker login your-registry.example.com
    ```
    If you are using Cloudron's built-in registry, you'll log in via the Cloudron CLI later if `cloudron build` doesn't handle it automatically.

3.  **Build the Docker Image**:
    Run the Cloudron build command from within the `activepices-cloudron` directory:
    ```bash
    cloudron build
    ```
    This command will:
    *   Read `CloudronManifest.json`.
    *   Build the Docker image using `Dockerfile`. This includes cloning the ActivePieces source from GitHub.
    *   Tag the image (e.g., `your-registry.example.com/yourusername/com.activepieces.cloudronapp:tag` or `cloudron/com.activepieces.cloudronapp:tag`).
    *   Push the image to the specified Docker registry. If no registry is specified, it will prompt for your Cloudron server details and use its registry.

    If you want to specify the image name and registry:
    ```bash
    cloudron build -t your-registry.example.com/yourusername/com.activepieces.cloudronapp:0.63.0-custom
    ```
    (Ensure the version tag is updated as needed).

## Deployment to Cloudron

1.  **Login to Cloudron (if not done by `cloudron build`):**
    ```bash
    cloudron login my.yourcloudron.server
    ```

2.  **Install the Application**:
    If `cloudron build` pushed to your Cloudron's registry (common case):
    ```bash
    cloudron install --image com.activepieces.cloudronapp:0.63.0 # Adjust image name/tag as built/pushed
    ```
    If you pushed to a different registry:
    ```bash
    cloudron install --image your-registry.example.com/yourusername/com.activepieces.cloudronapp:0.63.0-custom
    ```
    The CLI will prompt you for a location (e.g., `activepieces.yourcloudron.server`).

## Testing

1.  **Access the Application**: Open the URL provided after installation (e.g., `https://activepieces.yourcloudron.server`).
2.  **Initial Setup**: Follow the `postInstallMessage` from `CloudronManifest.json`. ActivePieces should guide you to create an admin account.
3.  **Core Functionality**:
    *   Test user registration and login.
    *   Create a simple automation flow (e.g., a webhook trigger and a notification action).
    *   Verify flows are saved (tests database connectivity).
    *   Verify flows execute (tests Redis connectivity for queues and backend processing).
    *   Test a few common "pieces" (integrations).
4.  **Check Logs**:
    View application logs via the Cloudron dashboard (Log Viewer) for any errors during startup or operation.
    ```bash
    cloudron logs -f --app activepieces.yourcloudron.server # Replace with your app's domain
    ```
5.  **Resource Usage**: Monitor memory and CPU usage from the Cloudron dashboard. Adjust `memoryLimit` in `CloudronManifest.json` and rebuild/reinstall if necessary. 1GB is a starting point; complex flows might need more.

## Important Verification Points (Crucial!)

*   **Environment Variables (`AP_*` in `start.sh`)**: This is the most critical part.
    *   Carefully review all `AP_` environment variables in `start.sh`.
    *   Compare them against the `.env.example` file in the cloned `activepieces_src` (version 0.63.0).
    *   Consult any official ActivePieces deployment documentation for the meaning and correct values/formats of these variables.
    *   Pay special attention to database, Redis, JWT, encryption, and email (SMTP) settings.
*   **Database Migrations (`start.sh`)**:
    *   Verify the `npm run migration:run:prod` or `npm run migration:run` command in `start.sh`.
    *   Check the `scripts` section of `activepieces_src/package.json` to confirm these scripts exist and are suitable for a production, post-build environment. The migration script might need to be adapted if it relies on TypeScript source files directly instead of compiled JavaScript.
    *   The original `docker-compose.yml` from ActivePieces used `npm run migration:run && npm run start`. The `migration:run` script in their `package.json` (v0.63.0) is `ts-node -r tsconfig-paths/register --transpileOnly src/app/database/migration/index.ts`. This will **not** work in our production container as `ts-node` and TypeScript sources are not available. The build process must output JavaScript migrations, and a script must exist to run these JS migrations. **This needs careful attention and likely modification in `start.sh` or the build process.**
*   **Frontend Asset Path (`Dockerfile` and `nginx.conf`)**:
    *   Verify the path `dist/packages/ui` used in the `Dockerfile` (for `COPY --from=builder`) and `nginx.conf` (for `root`).
    *   Inspect the `builder` stage of the Docker build or the `activepieces_src/dist/` directory after a local build to find the exact output path of the UI assets. It might be `dist/packages/ui/dist` or similar.
*   **`httpPort` and `AP_PORT`**:
    *   Ensure the internal port ActivePieces listens on (set by `AP_PORT` in `start.sh`, assumed 3000) matches `httpPort` in `CloudronManifest.json`.
*   **Email**: Test email sending (e.g., password reset, invites) to confirm SMTP variables in `start.sh` are correctly interpreted by ActivePieces.
*   **File Paths in `start.sh`**: Ensure paths to generated secrets (e.g., `/app/data/jwt_secret.txt`) are correct.
*   **Build Commands in `Dockerfile`**: Ensure `pnpm exec nx run-many --target=build --all --parallel=1` correctly builds all necessary production artifacts. Check `nx.json` and project-specific `project.json` files in `activepieces_src` for build configurations.

## Updating the Application

1.  **Update Source Version**:
    *   In the `Dockerfile`, change the `GIT_TAG` argument for the `git clone` command to the new ActivePieces version.
    *   Alternatively, if you manually manage `activepieces_src`, update its contents to the new version.
2.  **Manifest Version**: Update the `version` field in `CloudronManifest.json` to match the new ActivePieces version.
3.  **Rebuild**:
    ```bash
    cloudron build
    ```
    (Optionally with a new image tag: `-t your-registry/image-name:new-version`)
4.  **Update on Cloudron**:
    ```bash
    cloudron update --app activepieces.yourcloudron.server --image your-newly-built-image:tag
    ```
    Or, if using Cloudron's registry and the app ID matches the image name:
    ```bash
    cloudron update --app activepieces.yourcloudron.server
    ```
    Cloudron will pull the new image and restart the application, applying any new configurations from `start.sh` or database migrations.
