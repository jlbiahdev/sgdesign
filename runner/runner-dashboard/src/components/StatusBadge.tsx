import type { WorkStatus } from '@/lib/types'

export function StatusBadge({ status }: { status: WorkStatus }) {
  return (
    <span className="status-cell">
      <span className={`state-dot ${status}`} />
      <span className="status-text">{status}</span>
    </span>
  )
}
