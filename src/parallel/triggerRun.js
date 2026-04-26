const { execSync, spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const rootDir = path.resolve(__dirname, "../..");
const generatedDir = path.join(__dirname, "generated");

console.log("[INFO LOG] Generating test files...\n");
execSync(`node "${path.join(__dirname, "builder.js")}"`, {
  stdio: "inherit",
  cwd: rootDir,
});

const testFiles = fs
  .readdirSync(generatedDir)
  .filter((f) => f.endsWith(".js"))
  .sort()
  .map((f) => path.join("src", "parallel", "generated", f));

if (testFiles.length === 0) {
  console.error("[ERROR LOG] No test files were generated. Aborting.");
  process.exit(1);
}

console.log(
  `[INFO LOG] Running ${testFiles.length} test file(s) as parallel sessions...\n`,
);
const bsSDK = path.join(
  rootDir,
  "node_modules",
  ".bin",
  "browserstack-node-sdk",
);

const command = spawn(
  bsSDK,
  [
    "mocha",
    "src/parallel/generated/*.js",
    "--parallel",
    "--timeout",
    "1800000",
  ],
  {
    stdio: "inherit",
    shell: true,
    cwd: rootDir,
  },
);

command.on("exit", (exitCode) => {
  fs.rmSync(generatedDir, { recursive: true, force: true });
  console.log("[INFO LOG] Cleaned up generated test files.");
  process.exit(exitCode || 0);
});
