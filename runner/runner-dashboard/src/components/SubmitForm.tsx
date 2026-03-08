import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useSubmitTask } from '@/hooks/useTasks'
import type { CommandType, SubmitRequest } from '@/lib/types'

export function SubmitForm() {
  const navigate = useNavigate()
  const submit = useSubmitTask()

  const [form, setForm] = useState<SubmitRequest>({
    externalId: 1,
    commandType: 'Shell',
    exeName: '',
    args: null,
  })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const result = await submit.mutateAsync(form)
    navigate(`/tasks/${result.id}`)
  }

  return (
    <form onSubmit={handleSubmit} className="form-card">
      <div className="form-card-hdr">
        <div className="form-card-title">Soumettre une tâche</div>
        <div className="form-card-sub">
          {form.commandType === 'Shell' ? 'Exécution via Process.Start' : 'Exécution via ITaskHandler'}
        </div>
      </div>

      <div className="form-card-body">
        <div className="form-grid">

          <div className="fg-lbl">ID Externe</div>
          <div className="fg-ctrl">
            <input
              type="number"
              required
              min={0}
              value={form.externalId}
              onChange={(e) => setForm({ ...form, externalId: Number(e.target.value) })}
            />
          </div>

          <div className="fg-lbl">Type</div>
          <div className="fg-ctrl">
            <select
              value={form.commandType}
              onChange={(e) => setForm({ ...form, commandType: e.target.value as CommandType })}
            >
              <option value="Shell">Shell — Process.Start</option>
              <option value="DotNet">DotNet — ITaskHandler</option>
            </select>
          </div>

          <div className="fg-lbl">
            {form.commandType === 'Shell' ? 'Exécutable' : 'Nom du handler'}
          </div>
          <div className="fg-ctrl">
            <input
              type="text"
              required
              placeholder={form.commandType === 'Shell' ? 'echo' : 'EchoHandler'}
              value={form.exeName}
              onChange={(e) => setForm({ ...form, exeName: e.target.value })}
            />
          </div>

          <div className="fg-lbl nb">
            {form.commandType === 'Shell' ? 'Arguments' : 'Args JSON'}
          </div>
          <div className="fg-ctrl nb">
            <input
              type="text"
              placeholder={form.commandType === 'Shell' ? 'hello world' : '10'}
              value={form.args ?? ''}
              onChange={(e) => setForm({ ...form, args: e.target.value || null })}
            />
          </div>

        </div>
      </div>

      <div className="form-footer">
        <button type="submit" className="btn-submit" disabled={submit.isPending}>
          {submit.isPending ? 'Envoi…' : 'Soumettre'}
        </button>
        {submit.isError && (
          <span className="form-error">Erreur lors de la soumission.</span>
        )}
      </div>
    </form>
  )
}
