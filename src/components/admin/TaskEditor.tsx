import { useState } from 'react'
import { Modal } from '@/components/ui/Modal'
import { supabase } from '@/lib/supabase'
import type { Category, Priority, RecurrenceType, TaskTemplate } from '@/lib/types'
import { useStaff } from '@/hooks/useStaff'
import { useAuth } from '@/hooks/useAuth'

const CATEGORIES: Category[] = ['opening', 'bar', 'cleaning', 'closing', 'weekly', 'other']
const PRIORITIES: Priority[] = ['low', 'normal', 'high']
const WEEKDAYS = [
  { n: 1, label: 'Mon' },
  { n: 2, label: 'Tue' },
  { n: 3, label: 'Wed' },
  { n: 4, label: 'Thu' },
  { n: 5, label: 'Fri' },
  { n: 6, label: 'Sat' },
  { n: 7, label: 'Sun' },
]

export function TaskEditor({ task, onClose }: { task: TaskTemplate | null; onClose: () => void }) {
  const { staff } = useStaff()
  const { staff: me } = useAuth()
  const isNew = !task

  const [title, setTitle] = useState(task?.title ?? '')
  const [titleJa, setTitleJa] = useState(task?.title_ja ?? '')
  const [category, setCategory] = useState<Category>(task?.category ?? 'opening')
  const [assignedTo, setAssignedTo] = useState<string>(task?.assigned_to ?? '')
  const [isRecurring, setIsRecurring] = useState(task?.is_recurring ?? true)
  const [recurrenceType, setRecurrenceType] = useState<RecurrenceType>(task?.recurrence_type ?? 'daily')
  const [days, setDays] = useState<number[]>(task?.recurrence_days ?? [])
  const [priority, setPriority] = useState<Priority>(task?.priority ?? 'normal')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function toggleDay(n: number) {
    setDays((d) => (d.includes(n) ? d.filter((x) => x !== n) : [...d, n].sort()))
  }

  async function save() {
    if (!title.trim()) {
      setError('Title is required')
      return
    }
    setSaving(true)
    setError(null)
    const payload = {
      title: title.trim(),
      title_ja: titleJa.trim() || null,
      category,
      assigned_to: assignedTo || null,
      is_recurring: isRecurring,
      recurrence_type: isRecurring ? recurrenceType : null,
      recurrence_days: isRecurring && recurrenceType !== 'daily' ? days : [],
      priority,
      is_active: true,
    }
    try {
      if (isNew) {
        const { error } = await supabase
          .from('tasks')
          .insert({ ...payload, created_by: me?.id ?? null })
        if (error) throw error
      } else {
        const { error } = await supabase.from('tasks').update(payload).eq('id', task!.id)
        if (error) throw error
      }
      // Re-materialize today's daily_tasks so this shows up immediately
      await supabase.rpc('generate_daily_tasks')
      onClose()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open onClose={onClose} title={isNew ? 'New task' : 'Edit task'}>
      <div className="space-y-3">
        <Field label="Title (English)">
          <input className="input" value={title} onChange={(e) => setTitle(e.target.value)} />
        </Field>
        <Field label="Title (日本語)">
          <input className="input font-jp" value={titleJa} onChange={(e) => setTitleJa(e.target.value)} />
        </Field>

        <Field label="Category">
          <select className="input" value={category} onChange={(e) => setCategory(e.target.value as Category)}>
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </Field>

        <Field label="Assign to">
          <select className="input" value={assignedTo} onChange={(e) => setAssignedTo(e.target.value)}>
            <option value="">Unassigned (anyone can claim)</option>
            {staff
              .filter((s) => s.is_active)
              .map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
          </select>
        </Field>

        <Field label="Priority">
          <div className="flex gap-2">
            {PRIORITIES.map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => setPriority(p)}
                className={`flex-1 py-2 rounded-xl border text-sm capitalize ${
                  priority === p
                    ? 'bg-accent text-black border-accent'
                    : 'border-border text-neutral-300'
                }`}
              >
                {p}
              </button>
            ))}
          </div>
        </Field>

        <label className="flex items-center justify-between gap-2 py-1">
          <span className="text-sm text-neutral-300">Recurring</span>
          <input
            type="checkbox"
            checked={isRecurring}
            onChange={(e) => setIsRecurring(e.target.checked)}
            className="w-5 h-5 accent-accent"
          />
        </label>

        {isRecurring && (
          <>
            <Field label="Repeats">
              <select
                className="input"
                value={recurrenceType ?? 'daily'}
                onChange={(e) => setRecurrenceType(e.target.value as RecurrenceType)}
              >
                <option value="daily">Daily</option>
                <option value="weekly">Weekly (pick days)</option>
                <option value="monthly">Monthly (pick days of month)</option>
              </select>
            </Field>

            {recurrenceType === 'weekly' && (
              <Field label="Days of week">
                <div className="grid grid-cols-7 gap-1">
                  {WEEKDAYS.map((d) => (
                    <button
                      key={d.n}
                      type="button"
                      onClick={() => toggleDay(d.n)}
                      className={`py-2 rounded-lg border text-xs ${
                        days.includes(d.n)
                          ? 'bg-accent text-black border-accent'
                          : 'border-border text-neutral-400'
                      }`}
                    >
                      {d.label}
                    </button>
                  ))}
                </div>
              </Field>
            )}

            {recurrenceType === 'monthly' && (
              <Field label="Days of month (1–31, comma separated — empty = every day)">
                <input
                  className="input"
                  placeholder="1, 15"
                  value={days.join(', ')}
                  onChange={(e) =>
                    setDays(
                      e.target.value
                        .split(',')
                        .map((s) => parseInt(s.trim(), 10))
                        .filter((n) => Number.isFinite(n) && n >= 1 && n <= 31),
                    )
                  }
                />
              </Field>
            )}
          </>
        )}

        {error && (
          <div className="text-sm text-status-pending bg-status-pending/10 border border-status-pending/30 rounded-xl px-3 py-2">
            {error}
          </div>
        )}

        <div className="flex gap-2 pt-2">
          <button onClick={onClose} className="btn-secondary flex-1">
            Cancel
          </button>
          <button onClick={save} className="btn-primary flex-1" disabled={saving}>
            {saving ? 'Saving…' : isNew ? 'Create' : 'Save'}
          </button>
        </div>
      </div>
    </Modal>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="text-xs text-neutral-500 mb-1 block">{label}</label>
      {children}
    </div>
  )
}
