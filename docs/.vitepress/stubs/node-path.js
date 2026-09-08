// Browser stub: path resolution is never needed for url/bytes init.
export function resolve() {
  throw new Error("node:path is unavailable in the browser");
}
export function join() {
  throw new Error("node:path is unavailable in the browser");
}
export function dirname() {
  throw new Error("node:path is unavailable in the browser");
}
