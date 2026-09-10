#!/usr/bin/env node
// Minimal static server for the bundler matrix: serves one `.wasm` file
// with the correct MIME type. Usage: `node serve.mjs <wasm-file> <port>`.
import * as fs from "node:fs";
import * as http from "node:http";

const [wasmFile, portArg] = process.argv.slice(2);
if (!wasmFile) {
  console.error("usage: node serve.mjs <wasm-file> <port>");
  process.exit(1);
}
const port = Number.parseInt(portArg ?? "8123", 10);
const bytes = fs.readFileSync(wasmFile);
const server = http.createServer((request, response) => {
  if (request.url !== "/grammar.wasm") {
    response.writeHead(404);
    response.end();
    return;
  }
  response.writeHead(200, { "content-type": "application/wasm", "content-length": bytes.length });
  response.end(bytes);
});
server.listen(port, "127.0.0.1");
