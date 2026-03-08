import { useNavigate } from 'react-router-dom'
import { useCancelTask, useTasks } from '@/hooks/useTasks'
import { StatusBadge } from './StatusBadge'
import { formatDate } from '@/lib/utils'

export function TaskTable() {
  const { data: tasks = [], isLoading } = useTasks()
  const cancelTask = useCancelTask()
  const navigate = useNavigate()

  if (isLoading) return <p className="loading">Chargement des tâches…</p>

  return (
    <div className="table-card">
      <div className="monitor-wrap">
        <table className="monitor-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Type</th>
              <th>Commande</th>
              <th>Args</th>
              <th>État</th>
              <th>Créée le</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {tasks.length === 0 && (
              <tr>
                <td colSpan={7} className="table-empty">Aucune tâche pour l'instant</td>
              </tr>
            )}
            {tasks.map((t) => (
              <tr key={t.id}>
                <td className="col-id">#{t.id}</td>
                <td><span className="type-pill">{t.commandType}</span></td>
                <td className="col-exe">{t.exeName}</td>
                <td className="col-args">{t.args ?? '—'}</td>
                <td><StatusBadge status={t.state} /></td>
                <td>{formatDate(t.createdAt)}</td>
                <td>
                  <div className="btn-actions">
                    <button
                      className="btn-icon"
                      onClick={() => navigate(`/tasks/${t.id}`)}
                      title="Voir le détail"
                    >
                      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>
                      </svg>
                    </button>
                    {(t.state === 'Submitted' || t.state === 'Running') && (
                      <button
                        className="btn-icon danger"
                        onClick={() => cancelTask.mutate(t.id)}
                        title="Annuler"
                      >
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                          <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
                        </svg>
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
