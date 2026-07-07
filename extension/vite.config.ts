import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vitejs.dev/config/
export default defineConfig({
  resolve: {
    alias: {
      '@wasm': path.resolve(__dirname, './public/wasm')
    }
  },
  base: '',
  plugins: [
    react(),
    {
      name: 'manifest-plugin',
      generateBundle(_options, bundle) {
        const manifestAsset = bundle['manifest.json'];
        if (manifestAsset && manifestAsset.type === 'asset') {
          const manifest = JSON.parse(manifestAsset.source as string);
          
          if (process.env.BROWSER === 'firefox') {
            // Strip offscreen permission and service_worker for Firefox
            manifest.permissions = manifest.permissions.filter((p: string) => p !== 'offscreen');
            delete manifest.background.service_worker;
          } else {
            // Strip scripts and browser_specific_settings for Chrome
            delete manifest.background.scripts;
            delete manifest.browser_specific_settings;
          }
          
          manifestAsset.source = JSON.stringify(manifest, null, 2);
        }
      }
    }
  ],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/setupTests.ts',
  },
  build: {
    modulePreload: { polyfill: false },
    target: 'esnext',
    rollupOptions: {
      input: {
        popup: path.resolve(__dirname, 'popup.html'),
        offscreen: path.resolve(__dirname, 'offscreen.html'),
        resolve: path.resolve(__dirname, 'resolve.html'),
        background: path.resolve(__dirname, 'src/background/background.ts'),
      },
      output: {
        entryFileNames: (chunkInfo) => {
          if (chunkInfo.name === 'background') {
            return 'background.js';
          }
          return 'assets/[name]-[hash].js';
        }
      }
    }
  }
})
