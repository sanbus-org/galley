import { defineConfig } from "vite";

// Browser-demo bundle: same lib/es/minify-false/es2022 shape as the
// bundler-matrix fixtures, entry fixed on demo-browser.ts.
export default defineConfig({
  build: {
    lib: {
      entry: "demo-browser.ts",
      formats: ["es"],
      fileName: () => "app.bundle.js",
    },
    outDir: "dist-browser",
    emptyOutDir: true,
    minify: false,
    target: "es2022",
  },
});
