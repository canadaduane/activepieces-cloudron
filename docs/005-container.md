# Plan: Unify Builder and Final Stage Base Image to `cloudron/base:4.2.0`

## 1. Objective
To resolve persistent compatibility issues with native Node.js modules (like `bcrypt`) and simplify the Docker build process by using the same base image (`cloudron/base:4.2.0`) for both the `builder` stage and the `final` runtime stage. This aims to create a highly consistent environment between build-time and run-time.

## 2. Current Problem Recap
*   Native modules like `bcrypt` compiled in the `builder` stage (previously `node:18.20.5-bullseye-slim`) were incompatible with the `final` stage (`cloudron/base:4.2.0`, which uses Node 18.18.0 on Ubuntu Jammy).
*   Attempts to align Node.js versions or rebuild `bcrypt` in the final stage encountered complexities, including issues with `apt-get purge` affecting `supervisor`.

## 3. Proposed Change: Unified Base Image
Modify the `Dockerfile`'s `builder` stage to use `cloudron/base:4.2.0` as its `FROM` image, instead of `node:18.20.5-bullseye-slim`.

## 4. Ramifications and Considerations

### 4.1. Node.js Version in Builder Stage
*   **Impact:** The `cloudron/base:4.2.0` image provides Node.js v18.18.0. The entire build process in the `builder` stage (`npm ci`, `npx nx run-many ...`, `npm install --production --force`) will now use Node.js v18.18.0.
*   **Anticipation:**
    *   This is generally desirable, as the application will be built with the same Node.js version it will run with.
    *   If ActivePieces has a strict dependency on features only present in Node >18.18.0 (e.g., specific features in 18.20.5), this could be an issue. However, this seems unlikely for such minor version differences, and the original problem was compatibility with 18.18.0.
    *   The `npm i -g npm@9.9.3 pnpm@9.15.0` command in the builder stage will install these tools using the Node.js (and its npm) provided by `cloudron/base:4.2.0`. This should be fine.

### 4.2. Build Dependencies in `cloudron/base:4.2.0`
*   **Impact:** The `cloudron/base:4.2.0` image might not have all the build dependencies pre-installed that `node:18.20.5-bullseye-slim` plus our `apt-get install` line provided. We currently install: `openssh-client`, `python3`, `g++`, `build-essential`, `git`, `poppler-utils`, `procps`, `locales`, `locales-all`, `libcap-dev`.
*   **Anticipation:**
    *   We will need to ensure all these (or their equivalents for Ubuntu Jammy if names differ, though they are mostly standard) are installed in the `builder` stage *after* `FROM cloudron/base:4.2.0`.
    *   `python3`, `g++`, `build-essential`, `git` are critical for `npm ci` (for native modules) and `node-gyp`.
    *   `locales`, `locales-all`, `poppler-utils`, `procps` might be needed by ActivePieces or its dependencies. `libcap-dev` was also in the original list.
    *   The `cloudron/base` image likely has `python3` and basic build tools, but we must verify and add any missing ones.
    *   The `yarn config set python /usr/bin/python3` and `npm install -g node-gyp` steps will still be necessary.

### 4.3. Locale Configuration
*   **Impact:** The locale setup (`ENV LANG...`, `sed ... /etc/locale.gen`, `dpkg-reconfigure locales`) will need to be performed in the new `builder` stage based on `cloudron/base:4.2.0`.
*   **Anticipation:** This process should be similar, as `cloudron/base` is Debian-based (Ubuntu).

### 4.4. Simplification of `bcrypt` Handling
*   **Impact:** If the builder and final stages use the exact same base image (including OS, system libraries, and Node.js version), the `bcrypt.node` file compiled in the builder stage should work directly in the final stage.
*   **Anticipation:**
    *   The `RUN` command in the `final` stage to rebuild `bcrypt` (installing build tools, `npm rebuild bcrypt`, purging build tools) should **no longer be necessary**. This is a major simplification and avoids the `apt-get purge` issues we've been debugging.
    *   This also means the `apt-mark manual` for runtime dependencies, while good practice, becomes less critical for protecting against `bcrypt`'s build tool cleanup, as that cleanup step itself will be removed. We should keep `apt-mark manual` for general robustness.

### 4.5. `isolated-vm` Installation
*   **Impact:** The current `Dockerfile` installs `isolated-vm` in the `final` stage by running `npm i isolated-vm@5.0.1` in `/usr/src/isolated-vm-install`.
*   **Anticipation:**
    *   If `isolated-vm` is a native module, it too would benefit from being built in an environment identical to runtime.
    *   **Option 1 (Current approach, likely still fine):** Continue installing/building it in the `final` stage. Since this happens *within* the `final` stage, it uses the correct Node.js and system libraries from `cloudron/base:4.2.0`.
    *   **Option 2 (Alternative):** If we wanted to build it in the `builder` stage (now also `cloudron/base`), we could. Then, we'd copy the compiled `isolated-vm` from the builder to the final stage. However, `isolated-vm` seems to be installed globally/separately in the official ActivePieces Dockerfile, not as a direct project dependency, so the current method of installing it in the final stage is probably fine and mimics the official setup more closely.
    *   **Decision:** For now, keep the `isolated-vm` installation logic in the `final` stage as is. The primary goal is to fix `bcrypt` and other main application native dependencies.

### 4.6. Overall Dockerfile Structure
*   The `builder` stage will now start with `FROM cloudron/base:4.2.0 AS builder`.
*   It will need an `apt-get install` command for all necessary build tools (Node.js will be present, but `g++`, `python3`, `git`, `node-gyp` etc. need to be ensured).
*   The rest of the builder stage (`npm ci`, `nx build`, etc.) remains conceptually the same.
*   The `final` stage remains `FROM cloudron/base:4.2.0 AS final`.
*   Crucially, the `RUN` command for rebuilding `bcrypt` in the `final` stage (and installing/purging its build dependencies) **should be removed**.
*   The `apt-mark manual` for runtime dependencies in the `final` stage should be kept.

## 5. Plan of Action (Dockerfile Changes)

1.  **Modify `builder` Stage:**
    *   Change `FROM node:18.20.5-bullseye-slim AS builder` to `FROM cloudron/base:4.2.0 AS builder`.
    *   Add/verify `RUN apt-get update && apt-get install -y --no-install-recommends ...` for all build dependencies previously installed (e.g., `g++`, `build-essential`, `python3`, `git`, `locales-all`, `libcap-dev`, etc.). Note: `cloudron/base` already includes Node.js 18.18.0.
    *   Ensure `npm install -g node-gyp` is present.
    *   Keep locale configuration steps.
    *   The `npm ci` and `nx build` steps remain.
    *   The `RUN cd dist/packages/server/api && npm install --production --force` step in the builder (which installs/builds `bcrypt`) will now use Node 18.18.0 from `cloudron/base`.

2.  **Modify `final` Stage:**
    *   **Remove** the entire `RUN` block dedicated to installing build tools, rebuilding `bcrypt`, and purging build tools. This is the block that starts with `RUN apt-get update && apt-get install -y --no-install-recommends python3 build-essential g++ && ... npm rebuild bcrypt ...`.
    *   Keep the `RUN` block that installs runtime dependencies (`nginx`, `supervisor`, etc.) and includes `apt-mark manual ...`.

## 6. Expected Benefits
*   Elimination of native module (e.g., `bcrypt`) incompatibility errors due to environment mismatch.
*   Simplification of the `final` stage Dockerfile by removing the need for temporary build tool installation and `npm rebuild`.
*   Avoidance of complex `apt-get purge` issues that were affecting `supervisor`.
*   Potentially faster overall build times if the `cloudron/base` image is well-cached and if not having to rebuild `bcrypt` in the final stage saves time.
*   More stable and predictable builds.

## 7. Potential Risks
*   **Missing Dependencies in `cloudron/base` for Build:** We need to be thorough in adding back any build tools to the `builder` stage that were implicitly provided by `node:18.20.5-bullseye-slim` but might not be in `cloudron/base:4.2.0` (beyond Node.js itself).
*   **Application's True Node.js Requirement:** If ActivePieces *truly* needs >18.18.0 and this change forces it to build and run on 18.18.0, it might expose other, more subtle application-level issues. This is considered low risk for minor version differences.

## 8. Verification
*   After changes, build the Docker image.
*   Deploy and monitor logs for:
    *   Absence of `bcrypt_lib.node` errors.
    *   Absence of `supervisord: No such file or directory` errors.
    *   Successful application startup.
    *   Successful TypeORM migrations (this is a separate issue but good to check).
    *   Successful Nginx startup (also a separate issue).
