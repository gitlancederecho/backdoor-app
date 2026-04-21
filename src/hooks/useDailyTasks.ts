import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { todayIso } from '@/utils/date'
import type { DailyTask } from '@/lib/types'

const SELECT_WITH_JOINS = `
  *,
  task:tasks ( * ),
  assignee:staff!daily_tasks_assigned_to_fkey ( * ),
  completer:staff!daily_tasks_completed_by_fkey ( * )
`

export function useDailyTasks(date = todayIso()) {
  const [tasks, setTasks] = useState<DailyTask[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchTasks = useCallback(async () => {
    setError(null)
    const { data, error } = await supabase
      .from('daily_tasks')
      .select(SELECT_WITH_JOINS)
      .eq('date', date)
      .order('created_at', { ascending: true })

    if (error) {
      setError(error.message)
    } else {
      setTasks((data ?? []) as unknown as DailyTask[])
    }
    setLoading(false)
  }, [date])

  const ensureGenerated = useCallback(async () => {
    // Ask the server to materialize today's recurring instances if they don't exist yet.
    await supabase.rpc('generate_daily_tasks', { target_date: date })
  }, [date])

  useEffect(() => {
    let active = true
    ;(async () => {
      setLoading(true)
      await ensureGenerated()
      if (!active) return
      await fetchTasks()
    })()

    const channel = supabase
      .channel(`daily_tasks:${date}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'daily_tasks', filter: `date=eq.${date}` },
        () => {
          fetchTasks()
        },
      )
      .subscribe()

    return () => {
      active = false
      supabase.removeChannel(channel)
    }
  }, [date, fetchTasks, ensureGenerated])

  return { tasks, loading, error, refresh: fetchTasks }
}

export async function updateDailyTask(id: string, patch: Partial<DailyTask>) {
  const { error } = await supabase.from('daily_tasks').update(patch).eq('id', id)
  if (error) throw error
}
