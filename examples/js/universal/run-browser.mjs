#!/usr/bin/env node
// Runs the vite-bundled browser demo in headless Chromium and asserts its
// console output. Serve dist-browser/ over HTTP first, then:
//   node run-browser.mjs http://127.0.0.1:8123/index.html
// Anchor rows must appear in order; anything else (including page errors)
// fails loudly with the captured rows. Install the browser once with:
//   ./node_modules/.bin/playwright install --only-shell chromium

import { chromium } from "playwright";

const ANCHORS = [
  "galley version:",
  '@print "alpha"',
  "Document 2 pairs, sum=15",
  "parsed 15 bytes,",
  "diagnostic at 1:7:",
  "expected one of:",
  "while parsing (innermost first):",
  "recorded diagnostics: 3",
  "tree edit:",
];

function fatal(message) {
  console.error(`browser demo: ${message}`);
  process.exit(1);
}

const pageUrl = process.argv[2];
if (!pageUrl) fatal("usage: node run-browser.mjs <page-url>");

const lines = [];
// CI containers often run as root, where the sandbox refuses to start.
const browser = await chromium.launch({ args: ["--no-sandbox"] });
try {
  const page = await browser.newPage();
  page.on("console", (message) => {
    // Hook bodies log through console.error in browsers (process.stderr
    // on Node, Bun, and Deno); both types are demo output.
    if (message.type() === "log" || message.type() === "error") lines.push(message.text());
  });
  page.on("pageerror", (error) => {
    lines.push(`pageerror: ${error.message}`);
  });
  await page.goto(pageUrl, { waitUntil: "load" });
  const deadline = Date.now() + 30000;
  while (!lines.some((line) => line.startsWith("tree edit:")) && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
} finally {
  await browser.close();
}

let cursor = 0;
for (const anchor of ANCHORS) {
  const index = lines.findIndex((line, i) => i >= cursor && line.includes(anchor));
  if (index === -1) fatal(`missing console row: ${anchor}\n${lines.join("\n")}`);
  cursor = index + 1;
}
console.log(`browser demo: ${lines.length} console rows, anchors in order`);
