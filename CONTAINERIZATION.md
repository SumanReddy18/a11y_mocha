# SDK Containerization

How we run `a11y-mocha` against multiple BrowserStack envs without uninstalling
and reinstalling `browserstack-node-sdk` between runs.

## The problem

`browserstack-node-sdk` is fetched from a private GitHub repo, with a different
branch per environment:

| Env name      | SDK branch (`SDK_REF`)   |
|---------------|--------------------------|
| `rengg`       | `ai-a11y-one-day`        |
| `regression`  | `a11y-sdk-regression`    |
| `preprod`     | `a11y-sdk-preprod`       |
| `prod`        | `main`                   |

Previously, switching envs meant `rm -rf node_modules && npm install` against
the matching branch — a destructive, multi-minute operation. Each env also
needs its own BrowserStack `userName` / `accessKey`, which lived hardcoded in
`browserstack.yml` and had to be edited by hand.

## The approach

**One container image per env.** The SDK branch is baked into each image at
build time via a Docker build arg. Switching envs becomes a different image
tag — no host-side reinstall, multiple envs can run concurrently.

**Colima + nerdctl.** Builds and runs go through Colima's bundled `nerdctl`
on the `containerd` runtime. No Docker Engine, no Docker Desktop, no `docker`
CLI installed on the host.

**Single `keys.env` file in the repo.** All secrets — GitHub PAT (for fetching
the private SDK) and per-env BrowserStack credentials — live in one
gitignored file at the repo root. `run.sh` resolves the right pair per env at
invocation time.

```
                            ┌──────────────────┐
                            │ keys.env (600)   │  gitignored
                            │  GITHUB_TOKEN    │
                            │  RENGG_BS_USER   │
                            │  PREPROD_BS_USER │
                            │  ...             │
                            └────────┬─────────┘
                                     │ sourced by run.sh
                                     ▼
       ┌─────────────────────────────────────────────────┐
       │  ./run.sh preprod                               │
       │   ├─ resolves SDK_REF      = a11y-sdk-preprod   │
       │   ├─ resolves BS user/key  = PREPROD_*          │
       │   └─ resolves GITHUB_TOKEN = shared / per-env   │
       └────────┬─────────────────────────┬──────────────┘
                │                         │
                ▼                         ▼
        nerdctl build              nerdctl run
        --secret gh_token          -e BROWSERSTACK_USERNAME
        --build-arg SDK_REF        -e BROWSERSTACK_ACCESS_KEY
                │                         │
                ▼                         ▼
        a11y-mocha:preprod  ──────►  Container runs npm test
        (SDK baked in)               (creds from env, override yml)
```

## Files added

| File                     | Purpose                                                                   |
|--------------------------|---------------------------------------------------------------------------|
| `Dockerfile`             | `node:20-slim` + git/curl/build tools; takes `SDK_REF` as a build arg.    |
| `.dockerignore`          | Keeps `node_modules`, `log/`, `keys.env` out of the build context.        |
| `setup-colima.sh`        | One-time install: `brew install colima`; `colima start --runtime containerd`. |
| `run.sh`                 | Resolves env + creds, builds the right image (if missing), runs it.       |
| `keys.example.env`       | Sanitized template; copy to `keys.env` and fill in real values.           |
| `keys.env`               | Real secrets. **Gitignored. Never commit.**                               |
| `.gitignore`             | Adds `keys.env` and `*.local.env`.                                        |

## How the Dockerfile works

```dockerfile
ARG SDK_REF=ai-a11y-one-day
FROM node:20-slim
RUN apt-get install -y git ca-certificates curl python3 make g++

COPY package.json .npmrc* ./

RUN --mount=type=secret,id=gh_token,required=true \
    GH_TOKEN="$(cat /run/secrets/gh_token)" \
 && curl -fsSL -H "Authorization: token ${GH_TOKEN}" \
      -o /tmp/sdk.tgz \
      "https://api.github.com/repos/browserstack/browserstack-node-agent/tarball/${SDK_REF}" \
 && npm install /tmp/sdk.tgz \
 && rm -f /tmp/sdk.tgz \
 && cd node_modules/browserstack-node-sdk \
 && npm install \
 && npm run build-proto

COPY . .
CMD ["npm", "test"]
```

Why each piece:

1. **`SDK_REF` build arg** — varies the SDK branch per image without changing the file.
2. **`--mount=type=secret`** — BuildKit only exposes the PAT at `/run/secrets/gh_token` for the lifetime of one `RUN`. The token never ends up in any image layer or build cache.
3. **`curl … -H "Authorization: token …"`** — fetches the private repo's tarball through GitHub's API. We use a header (not a URL-embedded token) so the token doesn't leak into process listings, npm metadata, or `node_modules/**/_resolved`.
4. **`npm install /tmp/sdk.tgz`** — installs from a local tarball, then we delete it in the same `RUN` so the file never lands in a layer.
5. **`cd node_modules/browserstack-node-sdk && npm install && npm run build-proto`** — the SDK's own dev-deps + proto generation, mirroring the legacy `setup.sh` flow.

## How `run.sh` works

```
./run.sh <env> [--rebuild] [-- <extra mocha args>]
```

1. Maps the env name to an `SDK_REF` (table above).
2. Loads `./keys.env`, refusing if perms are looser than 600 or if git is tracking it.
3. Looks up `${ENV_UPPER}_BROWSERSTACK_USERNAME` / `_ACCESS_KEY` and an
   optional `${ENV_UPPER}_GITHUB_TOKEN` (falls back to shared `GITHUB_TOKEN`).
4. If the image `a11y-mocha:<env>` doesn't exist (or `--rebuild`):
   - Writes the resolved token to `~/.cache/a11y-mocha-gh-token` (mode 600).
   - Runs `nerdctl build --build-arg SDK_REF=… --secret id=gh_token,src=…`.
   - Cleans up the temp token on exit.
5. Runs the image with:
   - `-e BROWSERSTACK_USERNAME -e BROWSERSTACK_ACCESS_KEY` (only the resolved env's pair).
   - Bind mounts for `src/`, `data/`, `log/`, and `browserstack.yml` (read-only) so test edits don't trigger rebuilds.

## Setup (one time)

```bash
# 1. Install Colima (no Docker required)
./setup-colima.sh

# 2. Create the keys file from the template
cp keys.example.env keys.env
chmod 600 keys.env
$EDITOR keys.env    # paste real PAT + per-env BrowserStack creds
```

The PAT must be a fine-grained GitHub token with **Contents: Read** access to
`browserstack/browserstack-node-agent`. Create it at
<https://github.com/settings/personal-access-tokens>.

## Daily usage

```bash
./run.sh rengg              # build (first time) + run against rengg
./run.sh preprod            # different image, completely independent
./run.sh prod --rebuild     # refresh prod's image (e.g., after main moved)
./run.sh regression -- --grep "login"   # extra args to npm test / mocha
```

Switching envs is instant after the first build of each. Multiple envs can
build/run concurrently — they don't share `node_modules`.
