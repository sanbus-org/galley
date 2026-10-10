import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import process from "node:process";
import { WASI } from "node:wasi";

// Fallback wasm runner used by `zig build run-*` when wasmtime is not
// installed. Mirrors wasmtime's `--dir=.` invocation: the guest's cwd is
// the directory the build was invoked from, and the only preopened
// directory — input paths must be relative to it, since both runners deny
// absolute paths.

if (process.argv.length < 3) {
  console.error("usage: run-wasm.mjs <wasm-binary> [args...]");
  process.exit(2);
}

const wasmPath = resolve(process.argv[2]);
const cliArgs = process.argv.slice(3);

console.error(
  "note: running wasm under Node, which is slower than wasmtime; install wasmtime for full-speed runs",
);

const wasi = new WASI({
  version: "preview1",
  args: [wasmPath, ...cliArgs],
  env: process.env,
  preopens: {
    ".": process.cwd(),
  },
});

const bytes = await readFile(wasmPath);
const module = await WebAssembly.compile(bytes);
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
// wasi.start() returns the guest's exit code when it exits via proc_exit.
process.exitCode = wasi.start(instance);
