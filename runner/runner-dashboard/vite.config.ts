import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    port: 5173,
    proxy: {
      '/taskflow': {
        target: 'http://localhost:5000',
        changeOrigin: true,
        ws: true, // proxy WebSocket pour SignalR
      },
    },
  },
})
