const fs = require("fs");
const path = require("path");

const config = require("./config");

const rootDir = path.resolve(__dirname, "../..");
const csvPath = path.join(rootDir, "data", "urls.csv");
const generatedDir = path.join(__dirname, "generated");

// ---------------------------------------------------------------------------
// 1. Read URLs from urls.csv
// ---------------------------------------------------------------------------
if (!fs.existsSync(csvPath)) {
  console.error(`CSV file not found: ${csvPath}`);
  process.exit(1);
}

const urls = fs
  .readFileSync(csvPath, "utf-8")
  .split("\n")
  .map((u) => u.trim())
  .filter(Boolean);

if (urls.length === 0) {
  console.error(
    "No URLs found in data/urls.csv. Please populate the file and retry.",
  );
  process.exit(1);
}

// ---------------------------------------------------------------------------
// 2. Chunk URLs into batches of urlsPerFile
// ---------------------------------------------------------------------------
const { urlsPerFile } = config;
const batches = [];
for (let i = 0; i < urls.length; i += urlsPerFile) {
  batches.push(urls.slice(i, i + urlsPerFile));
}

console.log(
  `Total URLs: ${urls.length} | URLs per file: ${urlsPerFile} | Test files to generate: ${batches.length}`,
);

// ---------------------------------------------------------------------------
// 3. Clean and recreate the generated directory
// ---------------------------------------------------------------------------
if (fs.existsSync(generatedDir)) {
  fs.rmSync(generatedDir, { recursive: true, force: true });
}
fs.mkdirSync(generatedDir, { recursive: true });

// ---------------------------------------------------------------------------
// 4. Generate one test file per batch
// ---------------------------------------------------------------------------
batches.forEach((batch, index) => {
  const batchIndex = index + 1;
  const fileName = `test_${batchIndex}.js`;
  const filePath = path.join(generatedDir, fileName);

  fs.writeFileSync(filePath, generateTestContent(batch, batchIndex), "utf-8");
  console.log(`  Generated ${fileName}  (${batch.length} URLs)`);
});

console.log(`\nDone. Test files written to src/parallel/generated/`);

// ---------------------------------------------------------------------------
// Helper: build the JS source for a single generated test file
// ---------------------------------------------------------------------------
function generateTestContent(batchUrls, batchIndex) {
  const urlLines = batchUrls.map((u) => `    "${u}"`).join(",\n");

  const lines = [
    'const { Builder } = require("selenium-webdriver");',
    "",
    `describe("A11y Parallel Test Suite - Batch ${batchIndex}", function () {`,
    "  this.timeout(1800000);",
    "  let driver;",
    "",
    "  const urls = [",
    urlLines,
    "  ];",
    "",
    "  before(async function () {",
    "    try {",
    `      console.log("Initializing WebDriver for Batch ${batchIndex}...");`,
    '      driver = await new Builder().forBrowser("chrome").build();',
    "      await driver.manage().window().maximize();",
    `      console.log("WebDriver initialized for Batch ${batchIndex}");`,
    "    } catch (error) {",
    '      console.error("Failed to initialize WebDriver: " + error.message);',
    "      throw error;",
    "    }",
    "  });",
    "",
    `  it("Accessibility scan - Batch ${batchIndex}", async () => {`,
    `    console.log("Starting Batch ${batchIndex} with " + urls.length + " URLs");`,
    "    for (const url of urls) {",
    "      try {",
    '        console.log("Navigating to " + url);',
    "        await driver.get(url);",
    '        console.log("Navigation completed: " + url);',
    "",
    "        await driver.executeScript(`",
    "            return new Promise((resolve) => {",
    "                let totalHeight = 0;",
    "                const distance = 300;",
    "                const timer = setInterval(() => {",
    "                    const scrollHeight = document.body.scrollHeight;",
    "                    window.scrollBy(0, distance);",
    "                    totalHeight += distance;",
    "                    if (totalHeight >= scrollHeight) {",
    "                        clearInterval(timer);",
    "                        resolve();",
    "                    }",
    "                }, 50);",
    "            });",
    "        `);",
    "        await new Promise((resolve) => setTimeout(resolve, 500));",
    '        console.log("Finished scrolling: " + url);',
    "      } catch (error) {",
    '        console.error("Error processing " + url + ": " + error.message);',
    "      }",
    "    }",
    `    console.log("Batch ${batchIndex} completed");`,
    "  });",
    "",
    "  after(async function () {",
    "    if (driver) {",
    "      await driver.quit();",
    `      console.log("Browser closed for Batch ${batchIndex}");`,
    "    }",
    "  });",
    "});",
  ];

  return lines.join("\n") + "\n";
}
