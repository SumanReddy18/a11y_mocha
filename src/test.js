const { Builder } = require("selenium-webdriver");
const fs = require("fs");
const path = require("path");

describe("A11y Mocha Test Suite", function () {
  this.timeout(120000);
  let driver;

  before(async function () {
    try {
      console.log("Initializing WebDriver...");
      driver = await new Builder().forBrowser("chrome").build();
      await driver.manage().window().maximize();
      console.log("WebDriver initialized successfully");
    } catch (error) {
      console.error(`Failed to initialize WebDriver: ${error.message}`);
      throw error;
    }
  });

  it("Load test URLs and perform accessibility scan", async () => {
    const urlsFilePath = path.resolve(__dirname, "../data/urls.csv");
    const urls = fs
      .readFileSync(urlsFilePath, "utf-8")
      .split("\n")
      .filter(Boolean);

    console.log(`Starting test with URLs: ${JSON.stringify(urls)}`);

    for (const url of urls) {
      try {
        console.log(`Navigating to ${url}...`);
        await driver.get(url);
        console.log(`Navigation to ${url} completed`);

        console.log(`Scrolling to the bottom of ${url}...`);
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
        console.log(`Successfully scrolled to the bottom of ${url}`);
      } catch (error) {
        console.error(`Error processing ${url}: ${error.message}`);
      }
    }

    console.log("Test completed");
  });

  after(async function () {
    if (driver) {
      await driver.quit();
      console.log("Browser successfully closed");
    }
  });
});
