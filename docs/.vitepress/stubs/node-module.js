// Browser stubs for Node builtins the wasm adapter imports statically.
// The url/bytes init path never calls them; they exist only so the
// browser bundle resolves without Node polyfills. Scoped by the
// galley-node-stubs plugin to galley imports only — nothing else in the
// site is affected.
export function createRequire() {
  throw new Error("node:module is unavailable in the browser");
}
