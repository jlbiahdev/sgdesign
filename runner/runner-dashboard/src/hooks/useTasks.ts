import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from '@/lib/api'
import type { SubmitRequest } from '@/lib/types'

export function useTasks() {
  return useQuery({
    queryKey: ['tasks'],
    queryFn: api.tasks.list,
    refetchInterval: 30_000, // fallback polling si SignalR déconnecté
  })
}

export function useTask(id: number) {
  return useQuery({
    queryKey: ['task', id],
    queryFn: () => api.tasks.get(id),
  })
}

export function useTaskHistory(id: number) {
  return useQuery({
    queryKey: ['task-history', id],
    queryFn: () => api.tasks.history(id),
  })
}

export function useRunners() {
  return useQuery({
    queryKey: ['runners'],
    queryFn: api.runners.list,
    refetchInterval: 15_000,
  })
}

export function useSubmitTask() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (req: SubmitRequest) => api.tasks.submit(req),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['tasks'] }),
  })
}

export function useCancelTask() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: number) => api.tasks.cancel(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['tasks'] }),
  })
}
