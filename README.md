# ActivePieces for Cloudron

This repository contains the packaging files to build and run [ActivePieces](https://www.activepieces.com) on a [Cloudron](https://cloudron.io) instance.

**Tagline:** Open Source Business Automation

ActivePieces is a no-code business automation tool. Automate your work, integrate your apps, and build custom workflows without writing any code.

## About This Project

This project provides the necessary `Dockerfile`, `CloudronManifest.json`, and startup scripts (`start.sh`, `nginx.conf.template`, `supervisord.conf`) to package ActivePieces for easy deployment on Cloudron. The actual ActivePieces source code is expected to be located in the `./activepieces_src/` subdirectory.

For the official ActivePieces source code, please visit [github.com/activepieces/activepieces](https://github.com/activepieces/activepieces).

## Prerequisites

*   **Cloudron CLI**: Ensure the `cloudron` command-line tool is installed.
*   **Docker**: Docker must be installed and running on your build machine.
*   **ActivePieces Source**: The ActivePieces source code for the version you wish to package must be present in the `./activepieces_src/` directory relative to these packaging files.

## Building the Package

1.  **Navigate to Project Directory**:
    ```bash
    cd path/to/activepieces-cloudron
    ```

2.  **Prepare ActivePieces Source**:
    Ensure the `./activepieces_src/` directory contains the correct version of the ActivePieces source code.

3.  **Update Manifest (If Necessary)**:
    If you've updated the ActivePieces source code version, ensure the `upstreamVersion` and `version` fields in `CloudronManifest.json` are updated accordingly.

4.  **Build with Cloudron CLI**:
    ```bash
    cloudron build
    ```
    This command will build the Docker image and push it to the configured Docker registry. Note the image name and tag produced by the build process (e.g., `your-registry/your-image-name:tag` or `com.activepieces.cloudronapp:version`).

## Installing on Cloudron

1.  **Login to your Cloudron**:
    ```bash
    cloudron login my.yourcloudron.host
    ```

2.  **Install the Application**:
    Use the image name and tag from the `cloudron build` step.
    ```bash
    cloudron install --image your-registry/image-name:tag -l activepieces.yourcloudron.host
    ```
    Replace `your-registry/image-name:tag` with the actual image name (e.g., `yourdockerhubuser/com.activepieces.cloudronapp:0.63.0-cloudron1` or the image ID if using Cloudron's local registry) and `activepieces.yourcloudron.host` with your desired location.

For more detailed build notes, testing procedures, and update instructions, please refer to `ActivePieces-Build-Notes.md`.
