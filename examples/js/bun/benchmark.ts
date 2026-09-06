#!/usr/bin/env node
/**
 * JSON throughput through the Galley TypeScript bindings: no AST, no
 * procedures, no error recovery. Parses languages/json/samples/code-02.json
 * 10 times on one session and reports bytes/s.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { Session, libFileName } from "galley-js-bun";

const LOGICAL_INPUT = "languages/json/samples/code-02.json";
const DEFAULT_ITERATIONS = 10;

function resolveInput(explicit: string | undefined): string {
  if (explicit) return explicit;
  const checkout = process.env.GALLEY_CHECKOUT;
  if (checkout) {
    const candidate = path.join(checkout, LOGICAL_INPUT);
    if (fs.existsSync(candidate)) return candidate;
  }
  return path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..", LOGICAL_INPUT);
}

function jsonLibrary(): string {
  const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), "benchmark");
  const candidate = path.join(dir, libFileName());
  if (fs.existsSync(candidate)) return candidate;
  console.error(`missing ${candidate}`);
  process.exit(1);
}

function main(): number {
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
    session = new Session({ libraryPath: jsonLibrary() });
  } catch {
    console.error("failed to create a parser session");
    return 1;
  }

  try {
    let parsed: number;
    try {
      parsed = session.parseSentinel(data);
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
        parsed = session.parseSentinel(data);
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

process.exit(main());
