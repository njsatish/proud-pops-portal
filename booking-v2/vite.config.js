import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  base: './',
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: '../public-site',
    emptyOutDir: false,
    assetsDir: 'book2-assets',
    rollupOptions: {
      input: 'book2.html',
    },
  },
})
