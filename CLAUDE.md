# a11y_mocha

Accessibility (a11y) test harness that drives a list of URLs through Selenium + Mocha on BrowserStack. The actual a11y scanning is performed by the BrowserStack Node SDK (`browserstack-node-sdk`) wrapping the Mocha run; this repo just owns the driver script, the URL list, and the orchestration around it.

## What it does

- Reads URLs from `data/urls.csv` (one per line).
- For each URL: navigate, scroll to the bottom (to trigger lazy-loaded content), let the SDK's a11y scanner observe the page.
- Runs via the BrowserStack SDK so results land in BrowserStack Test Observability + Accessibility dashboards. Configured by `browserstack.yml` (WCAG 2.2 AAA, all issue types enabled, `accessibility: true`).

## Layout

```
src/
  test.js                 # Single Mocha suite, iterates all URLs in one session
  parallel/
    config.js             # urlsPerFile (batch size)
    builder.js            # Splits urls.csv into src/parallel/generated/test_N.js batches
    triggerRun.js         # Runs builder, then mocha --parallel over generated files, then cleans up
data/urls.csv             # Input URL list (newline-delimited)
browserstack.yml          # SDK + a11y scanner config
Dockerfile                # Bakes a chosen SDK branch into a per-env image
run.sh                    # Env-aware build + run via Colima/nerdctl
setup.sh                  # Host-side install (alternative to containerized run)
setup-colima.sh           # One-time Colima install + start (containerd runtime)
keys.env                  # Secrets, gitignored, must be mode 600
```

## Run modes

- `npm test` — serial: one Mocha session walks every URL in `urls.csv`.
- `npm run test:parallel` — generates one Mocha file per batch of `urlsPerFile` URLs (default 10, see `src/parallel/config.js`), then runs `mocha --parallel` so each batch is its own BrowserStack session. Generated files live in `src/parallel/generated/` and are cleaned up after the run.
- `npm run generate:parallel` — generate the batch files without running them (useful for inspection).

## Environments and the SDK branch model

The repo supports four envs, each pinned to a different branch of `browserstack/browserstack-node-agent` (the private SDK):

| Env          | SDK branch              |
|--------------|-------------------------|
| `rengg`      | `ai-a11y-one-day` (default) |
| `regression` | `a11y-sdk-regression`   |
| `preprod`    | `a11y-sdk-preprod`      |
| `prod`       | `main`                  |

Switching envs means switching SDK branches. To avoid mutating host `node_modules` every time, `run.sh` builds a separate Docker image per env (`a11y-mocha:<env>`) with the right SDK branch baked in. `setup.sh` is the non-containerized alternative — it wipes `node_modules` and reinstalls the SDK from the chosen branch.

## Containerized run (preferred)

```
./setup-colima.sh                  # one-time: install + start Colima (containerd)
./run.sh <env> [--rebuild] [-- <extra mocha args>]
```

`run.sh` shells out to `colima nerdctl --` (no Docker daemon required). It mounts `src/`, `data/`, `log/`, and `browserstack.yml` into the container so edits to the URL list or test code don't require a rebuild — only an SDK branch change does.

## Secrets (`keys.env`)

`run.sh` requires a single `keys.env` (default at repo root, override with `KEYS_FILE=...`). It must be:

- chmod 600 (run.sh refuses other modes)
- not tracked by git (run.sh refuses tracked or staged files)

Format (see `keys.example.env`):

```
GITHUB_TOKEN=ghp_xxx                        # PAT with Contents:Read on browserstack-node-agent
RENGG_BROWSERSTACK_USERNAME=...
RENGG_BROWSERSTACK_ACCESS_KEY=...
# ...same pattern for REGRESSION_, PREPROD_, PROD_
# Optional per-env override: <ENV>_GITHUB_TOKEN=...
```

The `GITHUB_TOKEN` is only used at image build time to fetch the private SDK tarball via a BuildKit secret mount (`--secret id=gh_token`); it is never written into a layer, `package.json`, or `package-lock.json`. The BrowserStack creds are passed as `-e` env vars at run time and consumed by `browserstack.yml` via `${...}` interpolation.

## Conventions and gotchas

- **Node 20+** is required (`engines` in `package.json`).
- **Mocha timeout is 30 minutes** (`this.timeout(1800000)`) — a single test iterates many URLs, so don't shorten it casually.
- **Per-URL errors are caught and logged**, not thrown. The suite is designed to keep going so one bad URL doesn't abort the whole run; check logs / BrowserStack dashboards for failures rather than relying on exit code alone.
- **`src/parallel/generated/` is ephemeral** — it's wiped at the start of `builder.js` and again after `triggerRun.js` finishes. Don't edit files there; edit `builder.js`'s template instead.
- **`browserstack.yml` interpolates env vars** (`${BROWSERSTACK_USERNAME}` etc.). Anything that runs the SDK must export those, plus `BUILD_NUMBER` for the `buildIdentifier`.
- **`package-lock.json` is committed**, but `setup.sh` deletes it when switching SDK branches because the lock pins the previous branch's tarball SHA.
- **Logs** land in `log/` (mounted into the container in `run.sh`); `log/events.json`, `log/usage.log`, and `log/performance-report/` are SDK-produced.
