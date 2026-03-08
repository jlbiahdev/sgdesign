import { useEffect, useRef } from 'react'
import * as signalR from '@microsoft/signalr'
import { useQueryClient } from '@tanstack/react-query'
import type { TaskEvent } from '@/lib/types'

const HUB_URL = '/taskflow/hub'

export function useSignalR() {
  const queryClient = useQueryClient()
  const connectionRef = useRef<signalR.HubConnection | null>(null)

  useEffect(() => {
    const connection = new signalR.HubConnectionBuilder()
      .withUrl(HUB_URL)
      .withAutomaticReconnect()
      .configureLogging(signalR.LogLevel.Information)
      .build()

    connection.on('RunnerChanged', () => {
      queryClient.invalidateQueries({ queryKey: ['runners'] })
    })

    connection.on('TaskStateChanged', (event: TaskEvent) => {
      console.log('[SignalR] TaskStateChanged', event)

      // Mise à jour optimiste du cache si la liste est déjà chargée
      queryClient.setQueryData<import('@/lib/types').TaskRecord[]>(['tasks'], (prev) => {
        if (!prev) return prev
        return prev.map((t) =>
          t.id === event.taskId ? { ...t, state: event.state } : t
        )
      })

      // Refetch systématique pour rester cohérent (même si setQueryData a réussi)
      queryClient.invalidateQueries({ queryKey: ['tasks'] })
      queryClient.invalidateQueries({ queryKey: ['task', event.taskId] })
      queryClient.invalidateQueries({ queryKey: ['task-history', event.taskId] })
    })

    connection.onreconnecting((err) => console.warn('[SignalR] Reconnecting…', err))
    connection.onreconnected((id) => console.info('[SignalR] Reconnected, id=', id))
    connection.onclose((err) => console.warn('[SignalR] Connection closed', err))

    connection.start()
      .then(() => console.info('[SignalR] Connected to', HUB_URL))
      .catch((err) => console.error('[SignalR] Failed to connect', err))
    connectionRef.current = connection

    return () => { connection.stop() }
  }, [queryClient])

  return connectionRef
}
