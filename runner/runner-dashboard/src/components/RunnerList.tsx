import { useRunners } from '@/hooks/useTasks'
import { formatDate, isAlive } from '@/lib/utils'

export function RunnerList() {
  const { data: runners = [], isLoading } = useRunners()

  if (isLoading) return <p className="loading">Chargement…</p>

  return (
    <div className="runners-card">
      <div className="runners-hdr">
        <span className="runners-hdr-title">Runners actifs</span>
        <span className="runners-count">{runners.length} enregistré{runners.length > 1 ? 's' : ''}</span>
      </div>

      {runners.length === 0 ? (
        <div className="runner-empty">Aucun runner enregistré</div>
      ) : (
        runners.map((r) => {
          const alive = isAlive(r.lastHeartbeatAt)
          return (
            <div key={r.id} className="runner-row">
              <span className={'state-dot ' + (alive ? 'Running' : 'Failed')} />
              <span className="runner-name">{r.friendlyName ?? r.id}</span>
              <span className="runner-id">{r.id}</span>
              <span className="runner-time">{formatDate(r.lastHeartbeatAt)}</span>
            </div>
          )
        })
      )}
    </div>
  )
}
