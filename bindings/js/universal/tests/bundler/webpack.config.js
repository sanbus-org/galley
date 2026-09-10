import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const entry = process.env.MATRIX_ENTRY ?? "./app-default.mjs";
const outDir = process.env.MATRIX_OUT ?? "dist-webpack-default";
// Default entry targets node (it needs node: builtins and resolves the
// `import` condition to the loader); the browser entry targets web.
// MATRIX_TARGET=node switches target, keeps node: imports external, and
// emits CJS (no module library).
const isNode = process.env.MATRIX_TARGET === "node";

export default {
  mode: "production",
  target: isNode ? "node" : "web",
  entry,
  ...(isNode ? { externalsPresets: { node: true } } : {}),
  output: {
    path: path.join(here, outDir),
    filename: isNode ? "app.bundle.cjs" : "app.bundle.js",
    clean: true,
    ...(isNode ? {} : { module: true, library: { type: "module" } }),
  },
  experiments: { outputModule: !isNode },
};
