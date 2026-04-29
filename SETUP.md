# Setup — Containerized run

Step-by-step guide to get `a11y_mocha` running in a container against any
BrowserStack env (`rengg`, `regression`, `preprod`, `prod`).

For *why* it's built this way (architecture, secret handling, image-per-env
model), see [`CONTAINERIZATION.md`](./CONTAINERIZATION.md).

## Prerequisites

- macOS with [Homebrew](https://brew.sh)
- A GitHub fine-grained Personal Access Token with **Contents: Read** on
  `browserstack/browserstack-node-agent`
  ([create one](https://github.com/settings/personal-access-tokens))
- BrowserStack `userName` + `accessKey` for each env you plan to run

You do **not** need Docker Desktop or Docker Engine.

## 1. One-time host setup

Install and start Colima (containerd runtime + bundled `nerdctl`):

```bash
./setup-colima.sh
```

This script is idempotent — re-running it is safe. It will:

- `brew install colima` (skipped if already present)
- start Colima with the `containerd` runtime, 4 CPU / 6 GiB RAM / 30 GiB disk
- run a `nerdctl info` sanity check

If Colima is already running on a different runtime (e.g. `docker`), the
script prints the command to switch — it won't stop your VM for you.

## 2. Create `keys.env`

All secrets for all envs live in a single file at the repo root.

```bash
cp keys.example.env keys.env
chmod 600 keys.env
$EDITOR keys.env
```

Fill in:

```bash
GITHUB_TOKEN=ghp_xxx                 # shared, used at build time only

RENGG_BROWSERSTACK_USERNAME=...
RENGG_BROWSERSTACK_ACCESS_KEY=...
REGRESSION_BROWSERSTACK_USERNAME=...
REGRESSION_BROWSERSTACK_ACCESS_KEY=...
PREPROD_BROWSERSTACK_USERNAME=...
PREPROD_BROWSERSTACK_ACCESS_KEY=...
PROD_BROWSERSTACK_USERNAME=...
PROD_BROWSERSTACK_ACCESS_KEY=...

# Optional — override the shared GitHub token for a specific env:
# PROD_GITHUB_TOKEN=ghp_yyy
```

Rules `run.sh` enforces (it will refuse to run otherwise):

- File must exist at `./keys.env` (or override with `KEYS_FILE=/some/path`)
- Permissions must be `600` or `400`
- Must **not** be tracked or staged by git
- `${ENV}_BROWSERSTACK_USERNAME` and `${ENV}_BROWSERSTACK_ACCESS_KEY` must be
  set for whichever env you're running

If `keys.env` ever ends up in git history, **rotate every credential in it** —
removing the file from the working tree doesn't remove it from history.

## 3. Build, rebuild, and run per env

```bash
./run.sh <env> [--rebuild] [-- <extra args>]
```

| Env          | Image tag              | SDK branch baked in        |
|--------------|------------------------|----------------------------|
| `rengg`      | `a11y-mocha:rengg`     | `ai-a11y-one-day` (default)|
| `regression` | `a11y-mocha:regression`| `a11y-sdk-regression`      |
| `preprod`    | `a11y-mocha:preprod`   | `a11y-sdk-preprod`         |
| `prod`       | `a11y-mocha:prod`      | `main`                     |

`run.sh` decides whether to build automatically:

- Image **doesn't exist** → builds, then runs.
- Image **exists** → reuses it (prints `✓ Reusing existing image …`), then runs.
- `--rebuild` passed → always builds, then runs.

You don't run a separate "build" command — the script handles it.

### First-time build per env

The first invocation against any env builds `a11y-mocha:<env>` from the
`Dockerfile` (fetches the matching SDK branch, installs deps, compiles
protos). This takes a few minutes. Every subsequent run for that env reuses
the cached image — startup is instant.

```bash
./run.sh rengg          # builds a11y-mocha:rengg, then runs
./run.sh preprod        # builds a11y-mocha:preprod, then runs
./run.sh regression     # builds a11y-mocha:regression, then runs
./run.sh prod           # builds a11y-mocha:prod, then runs
```

Each env produces a completely independent image — they don't share layers
beyond the `node:20-slim` base, and multiple envs can build/run concurrently
without conflict.

### Re-running (no rebuild)

```bash
./run.sh rengg                          # reuses cached image, instant start
./run.sh preprod                        # reuses cached image, instant start
./run.sh regression -- --grep "login"   # extra args forwarded to mocha
```

Edits to `src/`, `data/urls.csv`, or `browserstack.yml` are picked up via
bind mounts (see [Section 4](#4-whats-mounted-at-run-time)) — no rebuild
needed.

### Forcing a rebuild

Use `--rebuild` when the mapped SDK branch has moved, `package.json` or
`Dockerfile` changed, or you rotated the GitHub PAT:

```bash
./run.sh rengg --rebuild         # refresh after ai-a11y-one-day moved
./run.sh prod --rebuild          # refresh after main moved
./run.sh preprod --rebuild       # force a clean build of preprod
```

`--rebuild` only refreshes the env you name — other env images are untouched.

### Inspecting and cleaning up images

```bash
# List built images
colima nerdctl -- images | grep a11y-mocha

# Remove a single env's image (forces a fresh build next time)
colima nerdctl -- rmi a11y-mocha:preprod

# Remove all env images
colima nerdctl -- rmi a11y-mocha:rengg a11y-mocha:regression a11y-mocha:preprod a11y-mocha:prod
```

### Running multiple envs in parallel

Each env has its own image and its own `nerdctl run`, so you can fire them
in separate terminals concurrently:

```bash
# terminal 1
./run.sh rengg

# terminal 2
./run.sh preprod
```

They share Colima's VM resources but don't share `node_modules`, BS creds,
or build state.

## 4. What's mounted at run time

`run.sh` bind-mounts these into the container, so edits don't require a
rebuild:

| Host path             | Container path           | Mode |
|-----------------------|--------------------------|------|
| `./src`               | `/app/src`               | rw   |
| `./data`              | `/app/data`              | rw   |
| `./log`               | `/app/log`               | rw   |
| `./browserstack.yml`  | `/app/browserstack.yml`  | ro   |

Edit `data/urls.csv`, tweak a test, rerun — no rebuild needed. Only an SDK
branch change triggers a rebuild (via `--rebuild`).

## 5. When to rebuild

Rebuild with `./run.sh <env> --rebuild` when:

- The mapped SDK branch has new commits you want pulled in
- `package.json` or `Dockerfile` changed
- You rotated the GitHub PAT and the previous build cached a stale layer
  (rare — the PAT isn't cached, but a 401 from a prior build can be)

You don't need to rebuild for changes to `src/`, `data/`, `browserstack.yml`,
or anything else that's bind-mounted.

## Troubleshooting

**`colima not found`** → `./setup-colima.sh` first.

**`Colima isn't running`** → `colima start --runtime containerd`.

**`✗ keys.env has permissions 644`** → `chmod 600 keys.env`.

**`✗ keys.env is tracked by git`** → run.sh prints the exact untrack +
rotation steps. Follow them; assume the creds inside have leaked.

**`✗ RENGG_BROWSERSTACK_USERNAME or ..._ACCESS_KEY missing`** → add the
missing pair to `keys.env`. Variable names use the env name uppercased.

**Build fails fetching the SDK tarball (401/404)** → the PAT is missing
`Contents: Read` on `browserstack/browserstack-node-agent`, or the SDK branch
name has changed. Verify the token at
<https://github.com/settings/personal-access-tokens> and the branch name in
`run.sh:32-42`.

**Want to inspect generated parallel test files** → those are produced by
`npm run generate:parallel`, not by the container; see the main
[`README.md`](./README.md) for the parallel run mode.

## Where to look next

- [`CONTAINERIZATION.md`](./CONTAINERIZATION.md) — architecture and design rationale
- [`README.md`](./README.md) — what the suite does, run modes, layout
- [`CLAUDE.md`](./CLAUDE.md) — project conventions and gotchas
