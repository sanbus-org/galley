// Browser stub: the url/bytes init path never touches the filesystem.
export function accessSync() {
  throw new Error("node:fs is unavailable in the browser");
}
export function readFileSync() {
  throw new Error("node:fs is unavailable in the browser");
}
