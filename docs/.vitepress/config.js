import { defineConfig } from 'vitepress'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repository = process.env.GITHUB_REPOSITORY || 'sanbus-org/galley'
const configDir = path.dirname(fileURLToPath(import.meta.url))

// The wasm adapter statically imports Node builtins its browser path never
// calls. Rewrite those imports to throwing stubs, scoped to galley files
// only so the rest of the site keeps its real Node builtins.
const galleyNodeStubs = {
  'node:module': path.resolve(configDir, 'stubs/node-module.js'),
  'node:fs': path.resolve(configDir, 'stubs/node-fs.js'),
  'node:path': path.resolve(configDir, 'stubs/node-path.js'),
  'node:process': path.resolve(configDir, 'stubs/node-process.js')
}

function galleyNodeStubsPlugin() {
  return {
    name: 'galley-node-stubs',
    enforce: 'pre',
    resolveId(source, importer) {
      // Match both the symlinked (docs/node_modules/galley-js-*) and the
      // real (bindings/js/*) paths; nothing else in the site is affected.
      const fromGalley = importer &&
        (importer.includes('galley-js-') || importer.includes('/bindings/js/'));
      if (Object.hasOwn(galleyNodeStubs, source) && fromGalley) {
        return galleyNodeStubs[source];
      }
      return null;
    }
  };
}

const socialLink = { icon: 'github', link: `https://github.com/${repository}` }

export default defineConfig({
  title: 'Galley Compiler',
  description: 'Documentation for the Sanbus Galley parser generators and compiler.',
  base: '/',
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }]
  ],
  themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Try it', link: '/try-it' },
      { text: 'Documentation', link: '/getting_started' }
    ],
    sidebar: [
      {
        text: 'Introduction',
        items: [
          { text: 'Getting Started', link: '/getting_started' },
          { text: 'Using Galley as a Library', link: '/using-galley' },
          { text: 'Included Languages', link: '/languages' },
          { text: 'Configuration & Flags', link: '/configuration' },
          { text: 'Try it', link: '/try-it' }
        ]
      },
      {
        text: 'User Guide',
        items: [
          { text: 'Writing a Language', link: '/writing_a_language' },
          { text: 'Grammar Guidelines', link: '/grammar_guidelines' },
          { text: 'Reduction Procedures', link: '/procedures' },
          { text: 'Testing', link: '/testing' }
        ]
      },
      {
        text: 'Language Bindings',
        items: [
          { text: 'C and C++', link: '/bindings_c' },
          { text: 'Rust', link: '/bindings_rust' },
          { text: 'Go', link: '/bindings_go' },
          { text: 'Python', link: '/bindings_python' },
          { text: 'TypeScript', link: '/bindings_typescript' },
          { text: 'Deno', link: '/bindings_js_deno' },
          { text: 'Bun', link: '/bindings_js_bun' },
          { text: 'WebAssembly', link: '/bindings_js_wasm' },
          { text: 'Universal (npm)', link: '/bindings_js_universal' },
          { text: 'Java', link: '/bindings_java' }
        ]
      },
      {
        text: 'Advanced Architecture & Performance',
        items: [
          { text: 'Architecture', link: '/architecture' },
          { text: 'Syntax-Error Recovery & Messages', link: '/syntax_error_recovery' },
          { text: 'AST Node Allocations', link: '/ast_node_allocations' },
          { text: 'Benchmarks', link: '/benchmarks' },
          { text: 'Benchmark Layout Findings', link: '/benchmark_layout_findings' },
          { text: 'Benchmark Results', link: '/benchmark_results' }
        ]
      }
    ],
    socialLinks: [
      socialLink
    ]
  },
  vite: {
    plugins: [galleyNodeStubsPlugin()],
    optimizeDeps: {
      exclude: ['galley-js-wasm', 'galley-js-core']
    },
    server: {
      fs: {
        allow: ['..']
      }
    }
  }
})
