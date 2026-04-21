import { useMemo, useState } from 'react'
import { CATEGORY_LABELS, CATEGORY_ORDER, Category, DailyTask } from '@/lib/types'
import { TaskCard } from './TaskCard'
import { TaskCompletion } from './TaskCompletion'
import { formatDate, todayIso } from '@/utils/date'

export function TaskBoard({
  tasks,
  loading,
  error,
  filterMine,
  currentStaffId,
}: {
  tasks: DailyTask[]
  loading: boolean
  error: string | null
  filterMine?: boolean
  currentStaffId?: string
}) {
  const [selected, setSelected] = useState<DailyTask | null>(null)

  const visible = useMemo(() => {
    if (!filterMine || !currentStaffId) return tasks
    return tasks.filter((t) => t.assigned_to === currentStaffId)
  }, [tasks, filterMine, currentStaffId])

  const grouped = useMemo(() => {
    const map = new Map<Category, DailyTask[]>()
    for (const cat of CATEGORY_ORDER) map.set(cat, [])
    for (const t of visible) {
      const cat = (t.task?.category ?? 'other') as Category
      map.get(cat)?.push(t)
    }
    return map
  }, [visible])

  const total = visible.length
  const done = visible.filter((t) => t.status === 'completed').length

  return (
    <div className="px-4 pt-4">
      <div className="mb-4">
        <h1 className="text-2xl font-semibold">{formatDate(todayIso())}</h1>
        <p className="text-sm text-neutral-500 mt-0.5">
          {done}/{total} done{total > 0 && ` · ${Math.round((done / total) * 100)}%`}
        </p>
      </div>

      {error && (
        <div className="mb-3 text-sm text-status-pending bg-status-pending/10 border border-status-pending/30 rounded-xl px-3 py-2">
          {error}
        </div>
      )}

      {loading && <div className="text-neutral-500 text-sm">Loading tasks…</div>}

      {!loading && total === 0 && (
        <div className="card p-6 text-center text-neutral-500">
          No tasks for today. An admin can add recurring tasks or create one-off tasks.
        </div>
      )}

      <div className="space-y-5">
        {CATEGORY_ORDER.map((cat) => {
          const list = grouped.get(cat) ?? []
          if (list.length === 0) return null
          return (
            <section key={cat}>
              <h2 className="text-xs uppercase tracking-wider text-neutral-500 mb-2 flex items-baseline gap-2">
                {CATEGORY_LABELS[cat].en}
                <span className="font-jp">{CATEGORY_LABELS[cat].ja}</span>
                <span className="text-neutral-600">· {list.filter((t) => t.status === 'completed').length}/{list.length}</span>
              </h2>
              <div className="space-y-2">
                {list.map((t) => (
                  <TaskCard key={t.id} task={t} onClick={() => setSelected(t)} />
                ))}
              </div>
            </section>
          )
        })}
      </div>

      {selected && (
        <TaskCompletion
          task={selected}
          onClose={() => setSelected(null)}
        />
      )}
    </div>
  )
}
