#!/usr/bin/env node
/**
 * Parse throughput through the Galley TypeScript bindings: parses the
 * given sample on one session and reports bytes/s.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { galley } from "@sanbus/galley";
import type { Session } from "@sanbus/galley";

const DEFAULT_ITERATIONS = 10;

async function main(): Promise<number> {
  const arguments_ = process.argv.slice(2);
  // `--wasm` benchmarks the WebAssembly artifact explicitly: a `.wasm`
  // file misses the native leg and instantiates through wasm.
  const wasmMode = arguments_.includes("--wasm");
  const positional = arguments_.filter((argument) => argument !== "--wasm");
  if (positional.length < 2 || positional.length > 3) {
    console.error("usage: benchmark.ts [--wasm] <parser-dir> <sample-file> [iterations]");
    return 1;
  }
  const parserDir = positional[0];
  const filePath = positional[1];
  let iterations = DEFAULT_ITERATIONS;
  if (positional.length > 2) {
    iterations = Number.parseInt(positional[2], 10);
    if (!Number.isInteger(iterations) || iterations < 1) {
      console.error("iterations must be >= 1");
      return 1;
    }
  }

  let data: Buffer;
  try {
    data = fs.readFileSync(filePath);
  } catch {
    console.error(`failed to read ${filePath}`);
    return 1;
  }
  const length = data.length;

  let session: Session;
  try {
    if (wasmMode) {
      // Bare artifact loads wire nothing — fine for grammars whose
      // procedures live in the host entry.
      const parser = galley.load(path.join(parserDir, "libgalley-js-wasm.wasm"));
      session = parser.openSession();
    } else {
      // The entry is its parser: openSession returns a session directly.
      const entry = (await import(
        pathToFileURL(path.join(parserDir, "index.mjs")).href
      )) as { openSession: () => Session };
      session = entry.openSession();
    }
  } catch {
    console.error("failed to create a parser session");
    return 1;
  }

  try {
    let parsed = 0;
    // The first two parses are cold: the session arena grows during the
    // first and is reallocated for the second.
    for (let warmup = 0; warmup < 2; warmup++) {
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

    console.log(`input: ${filePath}`);
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
