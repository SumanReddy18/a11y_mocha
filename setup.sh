#!/bin/bash
set -e

if [ "$ENV" = "rengg" ]; then
    SDK_BRANCH="ai-a11y-sdk-rengg"
elif [ "$ENV" = "regression" ]; then
    SDK_BRANCH="a11y-sdk-regression"
elif [ "$ENV" = "preprod" ]; then
    SDK_BRANCH="a11y-sdk-preprod"
elif [ "$ENV" = "prod" ]; then
    SDK_BRANCH="main"
else
    SDK_BRANCH="ai-a11y-sdk-rengg"
fi

echo "Using SDK branch: $SDK_BRANCH based on ENV: $ENV"
echo "Removing existing node_modules and package-lock.json..."
rm -rf node_modules
rm -f package-lock.json

echo "Clearing npm cache..."
npm cache clean --force

echo "Installing SDK from branch: $SDK_BRANCH..."
npm install "git+https://github.com/browserstack/browserstack-node-agent.git#$SDK_BRANCH"

echo "Building the SDK..."
cd node_modules/browserstack-node-sdk/ && npm i && npm run build-proto
cd ../..

echo "Installing other project dependencies..."
npm install

echo "Setup complete!"
