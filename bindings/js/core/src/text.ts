/**
 * UTF-8 helpers shared by the core. `TextEncoder`/`TextDecoder` are provided
 * by Node, Bun, and Deno alike, so the core never touches `Buffer`.
 */

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function encodeUtf8(text: string): Uint8Array {
  return encoder.encode(text);
}

export function byteLengthUtf8(text: string): number {
  return encoder.encode(text).length;
}

export function decodeUtf8(bytes: Uint8Array): string {
  return decoder.decode(bytes);
}
