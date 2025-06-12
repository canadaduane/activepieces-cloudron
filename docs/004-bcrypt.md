# Plan to Resolve bcrypt_lib.node Error

## 1. Objective
Resolve the critical error: `Error: /app/code/backend/dist/packages/server/api/node_modules/bcrypt/lib/binding/napi-v3/bcrypt_lib.node: cannot open shared object file: No such file or directory`. This error causes the ActivePieces backend to crash and enter a restart loop.

## 2. Chosen Solution (Attempt 1 - Failed)
Implement "Option A" as outlined in `docs/003-errors.md#6-activepieces---bcrypt_libnode-missing`:
Align the Node.js version used in the `builder` stage of the `Dockerfile` with the Node.js version present in the `final` stage (runtime environment provided by `cloudron/base:4.2.0`).
**Result:** This did not resolve the issue. The error persists.

## 2.1 Chosen Solution (Attempt 2 - Current)
Implement "Option C" as outlined in `docs/003-errors.md#6-activepieces---bcrypt_libnode-missing`:
Rebuild `bcrypt` (and potentially other native modules) in the *final* stage of the `Dockerfile`. This ensures compilation against the exact runtime environment (Node.js version, OS, system libraries).
Additionally, we will revert the builder stage Node.js version to the original `node:18.20.5-bullseye-slim` as the primary build environment, since changing it did not help and rebuilding in the final stage is a more targeted fix for runtime compatibility.

## 3. Identified Runtime Node.js Version
The application logs indicate that the runtime Node.js version in the Cloudron environment is `v18.18.0`.

## 4. Dockerfile Modification Plan

The primary change will be in the `Dockerfile`.

*   **Current `builder` stage base image:**
    ```dockerfile
    FROM node:18.20.5-bullseye-slim AS builder
    ```

*   **`builder` stage base image (Reverted):**
    Revert to the original Node.js version for the builder stage, as changing it did not solve the problem and rebuilding in the final stage is now the primary strategy.
    ```dockerfile
    FROM node:18.20.5-bullseye-slim AS builder
    ```

*   **Proposed `final` stage modification:**
    Add steps to install build tools, rebuild `bcrypt`, and then remove build tools. This will happen after `node_modules` are copied from the builder.
    ```dockerfile
    # Stage 2: Final Cloudron Stage
    FROM cloudron/base:4.2.0 AS final
    
    # ... (existing RUN apt-get install for runtime dependencies) ...

    # Add build tools, rebuild bcrypt, then remove build tools
    RUN apt-get update && \
        apt-get install -y --no-install-recommends python3 build-essential g++ && \
        # Ensure the target directory for npm rebuild exists and has the package.json
        # bcrypt is a dependency of server-api
        cd /app/code/backend/dist/packages/server/api && \
        npm rebuild bcrypt --build-from-source && \
        apt-get purge -y --auto-remove python3 build-essential g++ && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*

    # ... (rest of the final stage Dockerfile) ...
    ```

## 5. Rationale for Change
*   Native Node.js addons like `bcrypt` are compiled C++ code that interfaces with Node.js. These addons are sensitive to the Node.js ABI (Application Binary Interface).
*   The ABI can change between different Node.js versions, even minor ones (e.g., 18.20.x vs. 18.18.x).
*   When `bcrypt` was compiled in the `builder` stage using Node.js `v18.20.5`, it produced a `.node` file compatible with that version's ABI.
*   Running this `.node` file with Node.js `v18.18.0` in the `final` stage leads to an ABI mismatch, causing the "cannot open shared object file" error (which often means it *can* find the file, but cannot load it due to incompatibility).
*   By rebuilding `bcrypt` directly within the `final` stage (which uses `cloudron/base:4.2.0` and its Node.js v18.18.0), we ensure it's compiled against the precise runtime environment, including the correct Node ABI, OS (Ubuntu Jammy), and system libraries (e.g., glibc version). This is more resilient than trying to perfectly match environments between builder and final stages.

## 6. Impact on Other Files or Configurations
*   This specific change to address the `bcrypt` error is localized to the `Dockerfile` (specifically the `FROM` instruction of the `builder` stage).
*   It does not necessitate direct changes to `start.sh`, `nginx.conf.template`, or `supervisord.conf` *for this particular issue*.
*   The other issues identified in `docs/003-errors.md` (e.g., TypeORM path, Nginx listen directive) will still require their respective planned modifications.

## 7. Code Removal
No specific lines of code need to be removed beyond modifying the `FROM` instruction in the `Dockerfile`.

## 8. Robustness of the Solution
*   Rebuilding native modules in the final stage is a common and robust pattern for Docker multi-stage builds when native module compatibility is critical and difficult to achieve by solely matching versions in a separate builder stage.
*   This approach directly addresses compatibility with the runtime environment.
*   The downside is a slight increase in layer size due to installing/uninstalling build tools, but it's often a necessary trade-off for reliability.

## 9. Verification Steps (Post-Implementation)
1.  Modify the `Dockerfile` as planned.
2.  Rebuild the Docker image.
3.  Deploy the new image to the Cloudron instance.
4.  Monitor the application logs closely during startup.
5.  Confirm that the `Error: ...bcrypt_lib.node: cannot open shared object file...` no longer appears.
6.  Verify that the ActivePieces backend process starts and remains running (i.e., does not enter a crash loop). This might still be affected by other errors if they are not yet fixed.

## 10. Potential Considerations and Risks
*   **Build Tools in Final Stage:** This approach requires temporarily installing build tools (`python3`, `g++`, `build-essential`) in the final image. These should be removed after `npm rebuild` to keep the final image lean.
*   **Correct `npm rebuild` Context:** The `npm rebuild bcrypt --build-from-source` command must be run in the directory containing the `node_modules` folder where `bcrypt` is located and its `package.json` (or the project's `package.json` that lists `bcrypt` as a dependency). For this project, it's `/app/code/backend/dist/packages/server/api`.
*   **Impact on Other Native Modules:** If other native modules are causing similar issues, they might also need to be included in the `npm rebuild` command (e.g., `npm rebuild bcrypt some-other-module`) or a general `npm rebuild --build-from-source` could be used, though rebuilding specific modules is safer.
*   **Build Time:** Rebuilding in the final stage can slightly increase Docker image build time.
*   **OS Differences (Builder vs. Final):** Reverting the builder to `node:18.20.5-bullseye-slim` while the final stage is `cloudron/base:4.2.0` (Ubuntu Jammy based) means the primary build of non-native parts happens on Debian, and native parts are rebuilt on Ubuntu. This is generally fine. The key is that the *native module compilation for runtime* happens in the runtime environment.
