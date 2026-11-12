import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // En GitHub Pages el sitio vive en https://usuario.github.io/repo/.
  // El workflow define VITE_BASE_PATH con el nombre del repositorio.
  base: process.env.VITE_BASE_PATH || '/',
})
