# Web A11y Mocha Test Suite

This project uses Mocha and Selenium WebDriver to perform a simple E2E test. It reads a list of URLs from a CSV file, navigates to each URL in a browser, and scrolls to the bottom of the page to perform web a11y automated scans

## Project Structure

```
/
|-- data/
|   `-- urls.csv         # CSV file with a list of URLs to test
|-- src/
|   `-- test.js          # The main test file with Mocha tests
|-- package.json         # Project dependencies and scripts
`-- README.md            # This file
```

## Prerequisites

- Node.js (version 20 or higher)

## Setup

1.  **Install SDK:**
    The SDK branch is `ai-a11y-sdk-rengg`.

    ```bash
    npm install git+https://github.com/browserstack/browserstack-node-agent.git#ai-a11y-sdk-rengg
    cd node_modules/browserstack-node-sdk/ && npm i && npm run build-proto
    cd ../..
    ```
    or run setup script

    ```bash
    ENV=rengg/regression/preprod/prod ./setup.sh
    ```

2.  **Install dependencies:**

    ```bash
    npm install
    ```

3.  **Add URLs:**
    Populate `data/urls.csv` with the URLs you want to test, one URL per line. For example:
    ```csv
    https://www.google.com
    https://www.github.com
    ```

## Running the tests

To run the tests, execute the following command:

```bash
npm test
```

This will launch a automate sdk session, navigate to each URL in `data/urls.csv`, and scroll to the bottom of the page.
