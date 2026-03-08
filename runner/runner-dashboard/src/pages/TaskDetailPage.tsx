import { useParams, Link } from 'react-router-dom'
import { useCancelTask, useTask, useTaskHistory } from '@/hooks/useTasks'
import { StatusBadge } from '@/components/StatusBadge'
import { formatDate } from '@/lib/utils'

export function TaskDetailPage() {
  const { id } = useParams<{ id: string }>()
  const taskId = Number(id)

  const { data: task, isLoading } = useTask(taskId)
  const { data: history = [] } = useTaskHistory(taskId)
  const cancelTask = useCancelTask()

  if (isLoading) return <p className="loading">Chargement…</p>
  if (!task) return <p className="loading" style={{ color: 'var(--red)' }}>Tâche introuvable.</p>

  return (
    <div style={{ maxWidth: 680 }}>
      <Link to="/" className="back-link">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <polyline points="15 18 9 12 15 6"/>
        </svg>
        Dashboard
      </Link>

      {/* Infos */}
      <div className="detail-card">
        <div className="detail-hdr">
          <span className="detail-title">Tâche #{task.id}</span>
          <StatusBadge status={task.state} />
        </div>
        {[
          ['ID Externe', task.externalId],
          ['Type',       task.commandType],
          ['Commande',   task.exeName],
          ['Arguments',  task.args ?? '—'],
          ['Créée le',   formatDate(task.createdAt)],
        ].map(([label, value]) => (
          <div key={label as string} className="detail-row">
            <span className="detail-key">{label}</span>
            <span className="detail-val">{value}</span>
          </div>
        ))}
      </div>

      {/* Cancel */}
      {(task.state === 'Submitted' || task.state === 'Running') && (
        <div style={{ marginBottom: 18 }}>
          <button
            className="btn-secondary"
            onClick={() => cancelTask.mutate(task.id)}
            disabled={cancelTask.isPending}
            style={{ color: 'var(--red)', borderColor: 'var(--red)' }}
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
            </svg>
            {cancelTask.isPending ? 'Annulation…' : 'Annuler la tâche'}
          </button>
        </div>
      )}

      {/* Timeline */}
      <div className="timeline-card">
        <div className="timeline-hdr">
          <span className="timeline-hdr-title">Historique des états</span>
        </div>
        {history.map((s) => (
          <div key={s.id} className="timeline-item">
            <div className="tl-state">
              <StatusBadge status={s.name} />
            </div>
            <span className="tl-time">{formatDate(s.createdAt)}</span>
            {s.reason && <span className="tl-reason">{s.reason}</span>}
            {s.serverId && <span className="tl-server">{s.serverId}</span>}
          </div>
        ))}
      </div>
    </div>
  )
}
