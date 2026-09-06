import { defineConfig } from 'vitepress'

const repository = process.env.GITHUB_REPOSITORY || 'sanbus-org/galley'

const socialLink = { icon: 'github', link: `https://github.com/${repository}` }

export default defineConfig({
  title: 'Galley Compiler',
  description: 'Documentation for the Sanbus Galley parser generators and compiler.',
  base: '/galley/',
  themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Documentation', link: '/getting_started' }
    ],
    sidebar: [
      {
        text: 'Introduction',
        items: [
          { text: 'Getting Started', link: '/getting_started' },
          { text: 'Using Galley as a Library', link: '/using-galley' },
          { text: 'Included Languages', link: '/languages' },
          { text: 'Configuration & Flags', link: '/configuration' }
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
    server: {
      fs: {
        allow: ['..']
      }
    }
  }
})
