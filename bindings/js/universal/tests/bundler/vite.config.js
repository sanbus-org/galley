import { defineConfig } from "vite";

const entry = process.env.MATRIX_ENTRY ?? "app-default.mjs";
const outDir = process.env.MATRIX_OUT ?? "dist-vite-default";

export default defineConfig({
  build: {
    lib: {
      entry,
      formats: ["es"],
      fileName: () => "app.bundle.js",
    },
    outDir,
    emptyOutDir: true,
    minify: false,
    target: "es2022",
  },
});
