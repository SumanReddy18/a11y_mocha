# syntax=docker/dockerfile:1.6
ARG NODE_VERSION=20
FROM node:${NODE_VERSION}-slim

ARG SDK_REF=ai-a11y-one-day
ENV SDK_REF=${SDK_REF}

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json .npmrc* ./

# The SDK repo is private. We fetch the tarball with a PAT mounted as a BuildKit
# secret (id=gh_token), then `npm install` from the local file. The token is
# never written to package.json, package-lock.json, or any image layer — the
# secret mount only exists for the duration of this RUN.
RUN --mount=type=secret,id=gh_token,required=true \
    GH_TOKEN="$(cat /run/secrets/gh_token)" \
 && curl -fsSL \
      -H "Authorization: token ${GH_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -o /tmp/sdk.tgz \
      "https://api.github.com/repos/browserstack/browserstack-node-agent/tarball/${SDK_REF}" \
 && npm install --no-audit --no-fund /tmp/sdk.tgz \
 && rm -f /tmp/sdk.tgz \
 && cd node_modules/browserstack-node-sdk \
 && npm install --no-audit --no-fund \
 && npm run build-proto

COPY . .

ENV NODE_ENV=production
CMD ["npm", "test"]
