import type { ServerRecord, SubmitRequest, TaskRecord, TaskStateRecord } from './types'

const BASE = '/taskflow'

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json', ...init?.headers },
    ...init,
  })
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
  if (res.status === 204) return undefined as T
  return res.json()
}

export const api = {
  tasks: {
    list: ()                    => request<TaskRecord[]>('/tasks'),
    get: (id: number)           => request<TaskRecord>(`/tasks/${id}`),
    history: (id: number)       => request<TaskStateRecord[]>(`/tasks/${id}/history`),
    submit: (body: SubmitRequest) => request<{ id: number }>('/tasks', {
      method: 'POST',
      body: JSON.stringify(body),
    }),
    cancel: (id: number) => request<void>(`/tasks/${id}`, { method: 'DELETE' }),
  },
  runners: {
    list: () => request<ServerRecord[]>('/runners'),
  },
}
