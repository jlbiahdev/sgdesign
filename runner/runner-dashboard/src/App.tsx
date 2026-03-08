import { useState, useEffect, useRef } from 'react'
import { Routes, Route, NavLink } from 'react-router-dom'
import * as signalR from '@microsoft/signalr'
import { useSignalR } from '@/hooks/useSignalR'
import { DashboardPage } from '@/pages/DashboardPage'
import { SubmitPage } from '@/pages/SubmitPage'
import { TaskDetailPage } from '@/pages/TaskDetailPage'

function useTheme() {
  const [theme, setTheme] = useState<'dark' | 'light'>(() => {
    return (localStorage.getItem('tf-theme') as 'dark' | 'light') ?? 'dark'
  })

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    localStorage.setItem('tf-theme', theme)
  }, [theme])

  return { theme, toggle: () => setTheme((t) => (t === 'dark' ? 'light' : 'dark')) }
}

function useSignalRConnected() {
  const connectionRef = useSignalR()
  const [connected, setConnected] = useState(false)
  const timerRef = useRef<ReturnType<typeof setInterval>>()

  useEffect(() => {
    timerRef.current = setInterval(() => {
      setConnected(connectionRef.current?.state === signalR.HubConnectionState.Connected)
    }, 1500)
    return () => clearInterval(timerRef.current)
  }, [connectionRef])

  return connected
}

export default function App() {
  const { theme, toggle } = useTheme()
  const connected = useSignalRConnected()

  return (
    <>
      <div className="header-top-bar" />

      <header>
        <div className="header-left">
          <div className="logo-text">
            <span className="logo-title">TaskFlow</span>
            <span className="logo-sub">Runner Dashboard</span>
          </div>

          <nav className="nav-links">
            <NavLink to="/" end className={({ isActive }) => 'nav-link' + (isActive ? ' active' : '')}>
              Dashboard
            </NavLink>
            <NavLink to="/submit" className={({ isActive }) => 'nav-link' + (isActive ? ' active' : '')}>
              + Nouvelle tâche
            </NavLink>
          </nav>
        </div>

        <div className="header-right">
          <div className="signalr-status">
            <span className={'signalr-dot ' + (connected ? 'live' : 'dead')} />
            <span className="signalr-lbl">{connected ? 'LIVE' : 'OFFLINE'}</span>
          </div>

          <div className="h-divider" />

          <div className="theme-toggle" onClick={toggle}>
            <span className="theme-lbl">{theme === 'dark' ? 'DARK' : 'LIGHT'}</span>
            <div className="theme-track"><div className="theme-thumb" /></div>
          </div>
        </div>
      </header>

      <main>
        <Routes>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/submit" element={<SubmitPage />} />
          <Route path="/tasks/:id" element={<TaskDetailPage />} />
        </Routes>
      </main>

      <footer>
        <span>TaskFlow Runner</span>
        <span>PostgreSQL · SignalR · .NET 8</span>
      </footer>
    </>
  )
}
