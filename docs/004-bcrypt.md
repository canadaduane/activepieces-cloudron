# Plan to Resolve bcrypt_lib.node Error

## 1. Objective
Resolve the critical error: `Error: /app/code/backend/dist/packages/server/api/node_modules/bcrypt/lib/binding/napi-v3/bcrypt_lib.node: cannot open shared object file: No such file or directory`. This error causes the ActivePieces backend to crash and enter a restart loop.

## 2. Chosen Solution
Implement "Option A" as outlined in `docs/003-errors.md#6-activepieces---bcrypt_libnode-missing`:
Align the Node.js version used in the `builder` stage of the `Dockerfile` with the Node.js version present in the `final` stage (runtime environment provided by `cloudron/base:4.2.0`).

## 3. Identified Runtime Node.js Version
The application logs indicate that the runtime Node.js version in the Cloudron environment is `v18.18.0`.

## 4. Dockerfile Modification Plan

The primary change will be in the `Dockerfile`.

*   **Current `builder` stage base image:**
    ```dockerfile
    FROM node:18.20.5-bullseye-slim AS builder
    ```

*   **Proposed `builder` stage base image:**
    Change to use Node.js v18.18.0. We will aim for a `bullseye-slim` variant if available for consistency with the previous base, otherwise a general `18.18.0` tag.
    ```dockerfile
    FROM node:18.18.0-bullseye-slim AS builder
    ```
    *If `node:18.18.0-bullseye-slim` is not available, `node:18.18.0` or `node:18.18-bullseye-slim` would be the next alternatives.*

## 5. Rationale for Change
*   Native Node.js addons like `bcrypt` are compiled C++ code that interfaces with Node.js. These addons are sensitive to the Node.js ABI (Application Binary Interface).
*   The ABI can change between different Node.js versions, even minor ones (e.g., 18.20.x vs. 18.18.x).
*   When `bcrypt` was compiled in the `builder` stage using Node.js `v18.20.5`, it produced a `.node` file compatible with that version's ABI.
*   Running this `.node` file with Node.js `v18.18.0` in the `final` stage leads to an ABI mismatch, causing the "cannot open shared object file" error (which often means it *can* find the file, but cannot load it due to incompatibility).
*   By compiling `bcrypt` (and other native addons) in the `builder` stage using the *exact same Node.js version* (`v18.18.0`) as the runtime environment, we ensure ABI compatibility.

## 6. Impact on Other Files or Configurations
*   This specific change to address the `bcrypt` error is localized to the `Dockerfile` (specifically the `FROM` instruction of the `builder` stage).
*   It does not necessitate direct changes to `start.sh`, `nginx.conf.template`, or `supervisord.conf` *for this particular issue*.
*   The other issues identified in `docs/003-errors.md` (e.g., TypeORM path, Nginx listen directive) will still require their respective planned modifications.

## 7. Code Removal
No specific lines of code need to be removed beyond modifying the `FROM` instruction in the `Dockerfile`.

## 8. Robustness of the Solution
*   Aligning Node.js versions for building and running native addons is a standard, reliable, and generally robust solution to prevent ABI mismatch errors.
*   This approach ensures that all native dependencies are compiled correctly for the target runtime environment from the outset.

## 9. Verification Steps (Post-Implementation)
1.  Modify the `Dockerfile` as planned.
2.  Rebuild the Docker image.
3.  Deploy the new image to the Cloudron instance.
4.  Monitor the application logs closely during startup.
5.  Confirm that the `Error: ...bcrypt_lib.node: cannot open shared object file...` no longer appears.
6.  Verify that the ActivePieces backend process starts and remains running (i.e., does not enter a crash loop). This might still be affected by other errors if they are not yet fixed.

## 10. Potential Considerations and Risks
*   **Availability of `node:18.18.0-bullseye-slim` Tag:** The exact Docker image tag `node:18.18.0-bullseye-slim` must exist on Docker Hub. If not, a close alternative like `node:18.18.0` (which usually defaults to a recent Debian base) or `node:18.18-bullseye` (if `bullseye-slim` specifically for 18.18.0 isn't tagged) will be used. The key is matching the `18.18.0` version.
*   **Operating System Base of `cloudron/base:4.2.0`:** The `cloudron/base:4.2.0` image is based on Ubuntu 22.04 (Jammy). The current builder uses `bullseye-slim` (Debian 11). While aligning Node.js versions is the primary fix for `.node` file issues, ideally, the builder's OS should also closely match the final stage's OS for maximum compatibility of system libraries.
    *   If `node:18.18.0-bullseye-slim` (or similar) resolves the `bcrypt` issue, it's acceptable.
    *   If issues persist that might be related to system libraries (unlikely for `bcrypt` itself but possible for other native modules), changing the builder base to something like `node:18.18.0-jammy-slim` (if available) would be a further step to consider. For now, aligning the Node version with the existing `bullseye-slim` base is the targeted first step.
*   **Future Cloudron Base Image Updates:** If Cloudron updates the Node.js version in future releases of `cloudron/base`, the `Dockerfile`'s builder stage might need to be updated again to maintain alignment. This is a standard part of Docker image maintenance.
