import React from 'react'
import ReactDOM from 'react-dom/client'

// Appliquer le thème avant le premier render (évite le flash)
document.documentElement.dataset.theme =
  (localStorage.getItem('tf-theme') as 'dark' | 'light') ?? 'dark'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import './index.css'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, staleTime: 10_000 },
  },
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </React.StrictMode>,
)
