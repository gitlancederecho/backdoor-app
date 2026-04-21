import { useMemo, useState } from 'react'
import { useDailyTasks } from '@/hooks/useDailyTasks'
import { useStaff } from '@/hooks/useStaff'
import { useTaskTemplates } from '@/hooks/useTaskTemplates'
import { TaskEditor } from '@/components/admin/TaskEditor'
import { StaffManager } from '@/components/admin/StaffManager'
import type { TaskTemplate } from '@/lib/types'
import { supabase } from '@/lib/supabase'
import { Avatar } from '@/components/tasks/TaskCard'

type Tab = 'overview' | 'tasks' | 'staff'

export default function Admin() {
  const [tab, setTab] = useState<Tab>('overview')

  return (
    <div className="px-4 pt-4">
      <h1 className="text-2xl font-semibold mb-4">Admin</h1>

      <div className="flex gap-2 mb-4 overflow-x-auto">
        {([
          ['overview', 'Overview'],
          ['tasks', 'Tasks'],
          ['staff', 'Staff'],
        ] as const).map(([k, label]) => (
          <button
            key={k}
            onClick={() => setTab(k)}
            className={`px-4 py-2 rounded-full text-sm border transition ${
              tab === k
                ? 'bg-accent text-black border-accent'
                : 'border-border text-neutral-300 hover:border-border-strong'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {tab === 'overview' && <Overview />}
      {tab === 'tasks' && <TasksAdmin />}
      {tab === 'staff' && <StaffManager />}
    </div>
  )
}

function Overview() {
  const { tasks: daily, loading } = useDailyTasks()
  const { staff } = useStaff()

  const total = daily.length
  const done = daily.filter((t) => t.status === 'completed').length
  const overdue = daily.filter((t) => t.status !== 'completed').length
  const pct = total === 0 ? 0 : Math.round((done / total) * 100)

  const perStaff = useMemo(() => {
    return staff
      .filter((s) => s.is_active)
      .map((s) => {
        const assigned = daily.filter((t) => t.assigned_to === s.id)
        const doneCount = assigned.filter((t) => t.status === 'completed').length
        return {
          staff: s,
          assigned: assigned.length,
          done: doneCount,
          rate: assigned.length === 0 ? 0 : Math.round((doneCount / assigned.length) * 100),
        }
      })
      .sort((a, b) => b.rate - a.rate)
  }, [staff, daily])

  if (loading) return <div className="text-neutral-500 text-sm">Loading…</div>

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-3 gap-2">
        <Stat label="Total" value={total} />
        <Stat label="Done" value={`${done} · ${pct}%`} tone="good" />
        <Stat label="Open" value={overdue} tone={overdue > 0 ? 'warn' : 'muted'} />
      </div>

      <section>
        <h2 className="text-xs uppercase tracking-wider text-neutral-500 mb-2">Per staff — today</h2>
        <div className="card divide-y divide-border">
          {perStaff.length === 0 && (
            <div className="p-4 text-sm text-neutral-500">No active staff.</div>
          )}
          {perStaff.map((row) => (
            <div key={row.staff.id} className="flex items-center gap-3 p-3">
              <Avatar name={row.staff.name} url={row.staff.avatar_url} size={32} />
              <div className="flex-1 min-w-0">
                <div className="font-medium truncate">{row.staff.name}</div>
                <div className="text-xs text-neutral-500">
                  {row.done}/{row.assigned} tasks · {row.rate}%
                </div>
              </div>
              <div className="w-16 h-1.5 bg-bg-elevated rounded-full overflow-hidden">
                <div
                  className="h-full bg-accent"
                  style={{ width: `${row.rate}%` }}
                />
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  )
}

function Stat({ label, value, tone = 'muted' }: { label: string; value: string | number; tone?: 'muted' | 'good' | 'warn' }) {
  const colors = tone === 'good' ? 'text-status-done' : tone === 'warn' ? 'text-status-pending' : 'text-neutral-100'
  return (
    <div className="card p-3">
      <div className="text-xs text-neutral-500">{label}</div>
      <div className={`text-xl font-semibold mt-1 ${colors}`}>{value}</div>
    </div>
  )
}

function TasksAdmin() {
  const { tasks, loading } = useTaskTemplates()
  const [editing, setEditing] = useState<TaskTemplate | 'new' | null>(null)

  async function deleteTask(id: string) {
    if (!confirm('Delete this task? This removes it from future days.')) return
    // Soft-delete: mark inactive. Keeps historical daily_tasks intact.
    await supabase.from('tasks').update({ is_active: false }).eq('id', id)
  }

  return (
    <div>
      <button className="btn-primary w-full mb-3" onClick={() => setEditing('new')}>
        + New task
      </button>

      {loading && <div className="text-neutral-500 text-sm">Loading…</div>}

      <div className="space-y-2">
        {tasks.map((t) => (
          <div key={t.id} className="card p-3 flex items-start gap-3">
            <div className="flex-1 min-w-0">
              <div className="flex items-baseline gap-2 flex-wrap">
                <span className="font-medium">{t.title}</span>
                {t.title_ja && <span className="font-jp text-sm text-neutral-400">{t.title_ja}</span>}
              </div>
              <div className="text-xs text-neutral-500 mt-1 flex flex-wrap gap-x-2">
                <span>{t.category}</span>
                <span>·</span>
                <span>{t.is_recurring ? `${t.recurrence_type ?? ''}` : 'one-off'}</span>
                {t.priority !== 'normal' && (
                  <>
                    <span>·</span>
                    <span className={t.priority === 'high' ? 'text-status-pending' : ''}>{t.priority}</span>
                  </>
                )}
              </div>
            </div>
            <div className="flex flex-col gap-1 shrink-0">
              <button onClick={() => setEditing(t)} className="text-sm text-accent px-2 py-1">Edit</button>
              <button onClick={() => deleteTask(t.id)} className="text-sm text-status-pending px-2 py-1">Delete</button>
            </div>
          </div>
        ))}
      </div>

      {editing && (
        <TaskEditor
          task={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
        />
      )}
    </div>
  )
}
