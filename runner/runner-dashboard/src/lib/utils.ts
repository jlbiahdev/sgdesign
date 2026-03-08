import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'
import type { WorkStatus } from './types'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function statusColor(status: WorkStatus): string {
  switch (status) {
    case 'Submitted': return 'bg-yellow-100 text-yellow-800'
    case 'Running':   return 'bg-blue-100 text-blue-800'
    case 'Finished':  return 'bg-green-100 text-green-800'
    case 'Failed':    return 'bg-red-100 text-red-800'
    case 'Canceled':  return 'bg-gray-100 text-gray-600'
  }
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleString('fr-FR', {
    dateStyle: 'short',
    timeStyle: 'medium',
  })
}

export function isAlive(lastHeartbeat: string, thresholdSeconds = 60): boolean {
  const diff = (Date.now() - new Date(lastHeartbeat).getTime()) / 1000
  return diff < thresholdSeconds
}
