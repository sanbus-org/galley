#!/usr/bin/env node
/**
 * JSON throughput through the Galley TypeScript bindings: no AST, no
 * procedures, no error recovery. Parses languages/json/samples/code-02.json
 * 10 times on one session and reports bytes/s.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import process from "node:process";
import { galley } from "@sanbus/galley";
import type { Session } from "@sanbus/galley";
import * as json from "./json/index.mjs";

const LOGICAL_INPUT = "languages/json/samples/code-02.json";
const DEFAULT_ITERATIONS = 10;

function resolveInput(explicit: string | undefined): string {
  if (explicit) return explicit;
  const checkout = process.env.GALLEY_CHECKOUT;
  if (checkout) {
    const candidate = path.join(checkout, LOGICAL_INPUT);
    if (fs.existsSync(candidate)) return candidate;
    console.error(`GALLEY_CHECKOUT=${checkout} has no ${LOGICAL_INPUT}`);
    process.exit(1);
  }
  console.error(`pass the sample file or set GALLEY_CHECKOUT at a Galley checkout (needs ${LOGICAL_INPUT})`);
  process.exit(1);
}

// GALLEY_WASM=1 (or a path to a `.wasm` module file) benchmarks the
// WebAssembly backend instead of native, mirroring demo.ts.
function jsonWasmBytes(): Uint8Array | "dir" | null {
  const selected = process.env.GALLEY_WASM;
  if (!selected) return null;
  process.env.GALLEY_QUIET = "1";
  if (selected === "1") return "dir";
  return new Uint8Array(fs.readFileSync(selected));
}

async function main(): Promise<number> {
  const arguments_ = process.argv.slice(2);
  let iterations = DEFAULT_ITERATIONS;
  const explicit = arguments_[0];
  if (arguments_.length > 1) {
    iterations = Number.parseInt(arguments_[1], 10);
    if (!Number.isInteger(iterations) || iterations < 1) {
      console.error("iterations must be >= 1");
      return 1;
    }
  }

  const filePath = resolveInput(explicit);
  let data: Buffer;
  try {
    data = fs.readFileSync(filePath);
  } catch {
    console.error(`failed to read ${LOGICAL_INPUT}`);
    return 1;
  }
  const length = data.length;

  let session: Session;
  try {
    await json.initialize();
    const wasm = jsonWasmBytes();
    if (wasm !== null && wasm !== "dir") {
      const language = await galley.loadBytes(wasm);
      session = await language.openSession();
    } else {
      session =
        wasm === null
          ? await json.openSession()
          : await json.openSession({ backend: "wasm" });
    }
  } catch {
    console.error("failed to create a parser session");
    return 1;
  }

  try {
    let parsed: number;
    try {
      parsed = session.parse(data);
    } catch (err: unknown) {
      console.error(`warmup parse failed: ${err}`);
      return 1;
    }
    if (parsed !== length) {
      console.error(`warmup parse failed: parsed ${parsed} of ${length} bytes`);
      return 1;
    }

    const start = process.hrtime.bigint();
    let index = 0;
    try {
      for (; index < iterations; index++) {
        parsed = session.parse(data);
        if (parsed !== length) break;
      }
    } catch (err: unknown) {
      console.error(`parse failed at iteration ${index}: ${err}`);
      return 1;
    }
    const elapsed = process.hrtime.bigint() - start;
    if (parsed !== length) {
      console.error(`parse failed at iteration ${index}: parsed ${parsed} of ${length} bytes`);
      return 1;
    }
    const total = BigInt(length) * BigInt(iterations);
    const bps = elapsed === 0n ? 0n : (total * 1_000_000_000n) / elapsed;

    console.log(`input: ${LOGICAL_INPUT}`);
    console.log(`bytes: ${withThousands(length)}`);
    console.log(`iterations: ${withThousands(iterations)}`);
    console.log(`parsed_bytes: ${withThousands(total)}`);
    console.log(`duration_ns: ${withThousands(elapsed)}`);
    console.log(`bytes_per_second: ${withThousands(bps)}`);
    return 0;
  } finally {
    session.close();
  }
}

function withThousands(n: number | bigint): string {
  const digits = n.toString();
  let out = "";
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ",";
    out += digits[i];
  }
  return out;
}

main().then((code) => process.exit(code));
