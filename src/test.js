const { Builder } = require("selenium-webdriver");
const fs = require("fs");
const path = require("path");

describe("A11y Mocha Test Suite", function () {
  this.timeout(1800000);
  let driver;

  before(async function () {
    try {
      console.log("[INFO LOG] Initializing WebDriver...");
      driver = await new Builder().forBrowser("chrome").build();
      await driver.manage().window().maximize();
      console.log("[INFO LOG] WebDriver initialized successfully");
    } catch (error) {
      console.error(`[ERROR LOG] Failed to initialize WebDriver: ${error.message}`);
      throw error;
    }
  });

  it("Load test URLs and perform accessibility scan", async () => {
    const urlsFilePath = path.resolve(__dirname, "../data/urls.csv");
    const urls = fs
      .readFileSync(urlsFilePath, "utf-8")
      .split("\n")
      .filter(Boolean);

    console.log(`[INFO LOG] Starting test with URLs: ${JSON.stringify(urls)}`);

    for (const url of urls) {
      try {
        console.log(`[INFO LOG] Navigating to ${url}...`);
        await driver.get(url);
        console.log(`[INFO LOG] Navigation to ${url} completed`);

        console.log(`[INFO LOG] Scrolling to the bottom of ${url}...`);
        await driver.executeScript(`
            return new Promise((resolve) => {
                let totalHeight = 0;
                const distance = 300;
                const timer = setInterval(() => {
                    const scrollHeight = document.body.scrollHeight;
                    window.scrollBy(0, distance);
                    totalHeight += distance;

                    if (totalHeight >= scrollHeight) {
                        clearInterval(timer);
                        resolve();
                    }
                }, 50);
            });
        `);
        await new Promise((resolve) => setTimeout(resolve, 500));
        console.log(`[INFO LOG] Successfully scrolled to the bottom of ${url}`);
      } catch (error) {
        console.error(`[ERROR LOG] Error processing ${url}: ${error.message}`);
      }
    }

    console.log("[INFO LOG] Test completed");
  });

  after(async function () {
    if (driver) {
      await driver.quit();
      console.log("[INFO LOG] Browser successfully closed");
    }
  });
});
