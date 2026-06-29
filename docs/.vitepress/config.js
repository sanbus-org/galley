import { defineConfig } from 'vitepress'

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
          { text: 'Included Languages', link: '/languages' },
          { text: 'Configuration & Flags', link: '/configuration' }
        ]
      },
      {
        text: 'User Guide',
        items: [
          { text: 'Writing a Language', link: '/writing_a_language' },
          { text: 'Grammar Guidelines', link: '/grammar_guidelines' }
        ]
      },
      {
        text: 'Advanced Architecture & Performance',
        items: [
          { text: 'Core Architecture', link: '/architecture' },
          { text: 'AST Node Allocations', link: '/ast_node_allocations' },
          { text: 'Benchmarks', link: '/benchmarks' }
        ]
      }
    ],
    socialLinks: [
      {
        icon: {
          svg: "<svg xmlns='http://www.w3.org/2000/svg' viewBox='-.1 -.1 4.433 4.433' width='16' height='16' fill='#2185d0'><defs><linearGradient id='codeberg-gradient' gradientUnits='userSpaceOnUse' x1='42519.285' y1='-7078.7891' x2='42575.336' y2='-6966.9307'><stop stop-color='#2185d0' stop-opacity='0'/><stop offset='.495' stop-color='#2185d0' stop-opacity='.3'/></linearGradient></defs><g transform='matrix(.0655 0 0 .0655-2.232-1.4317)'><path d='m42519.285-7078.7891a.76086879.56791688 0 0 0-.738.6739l33.586 125.8886a87.182358 87.182358 0 0 0 39.381-33.7636l-71.565-92.5196a.76086879.56791688 0 0 0-.664-.2793z' transform='matrix(.37058478 0 0 .37058478 -15690 2662)' fill='url(#codeberg-gradient)'/><path d='m11249.461-1883.6961c-12.74 0-23.067 10.3275-23.067 23.0671 0 4.3335 1.22 8.5795 3.522 12.2514l19.232-24.8636c.138-.1796.486-.1796.624 0l19.233 24.8646c2.302-3.6721 3.523-7.9185 3.523-12.2524 0-12.7396-10.327-23.0671-23.067-23.0671z' transform='matrix(1.4006354 0 0 1.4006354-15690 2662)'/></g></svg>"
        },
        link: 'https://codeberg.org/sassanh/galley'
      }
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
