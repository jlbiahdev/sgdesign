import { useTasks } from '@/hooks/useTasks'
import { RunnerList } from '@/components/RunnerList'
import { TaskTable } from '@/components/TaskTable'
import { Link } from 'react-router-dom'
import type { WorkStatus } from '@/lib/types'

const STATUSES: WorkStatus[] = ['Submitted', 'Running', 'Finished', 'Failed', 'Canceled']

export function DashboardPage() {
  const { data: tasks = [] } = useTasks()

  const counts = STATUSES.reduce((acc, s) => {
    acc[s] = tasks.filter((t) => t.state === s).length
    return acc
  }, {} as Record<WorkStatus, number>)

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Dashboard</div>
          <div className="page-sub">{tasks.length} tâche{tasks.length > 1 ? 's' : ''} au total</div>
        </div>
        <Link to="/submit" className="btn-submit">+ Nouvelle tâche</Link>
      </div>

      <div className="stats-row">
        {STATUSES.map((s) => (
          <div key={s} className={'stat-card' + (counts[s] > 0 ? ' has-value' : '')}>
            <div className="stat-num">{counts[s]}</div>
            <div className="stat-label">
              <span className={`state-dot ${s}`} />
              {s}
            </div>
          </div>
        ))}
      </div>

      <RunnerList />
      <TaskTable />
    </div>
  )
}
