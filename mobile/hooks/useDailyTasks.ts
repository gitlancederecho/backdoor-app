import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { todayIso } from '@/utils/date'
import type { DailyTask } from '@/lib/types'

const SELECT = `*, task:tasks(*), assignee:staff!daily_tasks_assigned_to_fkey(*), completer:staff!daily_tasks_completed_by_fkey(*)`

export function useDailyTasks(date = todayIso()) {
  const [tasks, setTasks] = useState<DailyTask[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchTasks = useCallback(async () => {
    setError(null)
    const { data, error } = await supabase
      .from('daily_tasks')
      .select(SELECT)
      .eq('date', date)
      .order('created_at', { ascending: true })
    if (error) setError(error.message)
    else setTasks((data ?? []) as unknown as DailyTask[])
    setLoading(false)
    setRefreshing(false)
  }, [date])

  const pullRefresh = useCallback(async () => {
    setRefreshing(true)
    await fetchTasks()
  }, [fetchTasks])

  useEffect(() => {
    let active = true
    ;(async () => {
      setLoading(true)
      await supabase.rpc('generate_daily_tasks', { target_date: date })
      if (!active) return
      await fetchTasks()
    })()

    const channel = supabase
      .channel(`daily_tasks_mobile:${date}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'daily_tasks', filter: `date=eq.${date}` }, () => {
        fetchTasks()
      })
      .subscribe()

    return () => {
      active = false
      supabase.removeChannel(channel)
    }
  }, [date, fetchTasks])

  return { tasks, loading, refreshing, error, refresh: fetchTasks, pullRefresh }
}

export async function updateDailyTask(id: string, patch: Partial<DailyTask>) {
  const { error } = await supabase.from('daily_tasks').update(patch).eq('id', id)
  if (error) throw error
}
