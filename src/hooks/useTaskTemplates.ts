import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { TaskTemplate } from '@/lib/types'

export function useTaskTemplates() {
  const [tasks, setTasks] = useState<TaskTemplate[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchTasks = useCallback(async () => {
    setError(null)
    const { data, error } = await supabase
      .from('tasks')
      .select('*')
      .eq('is_active', true)
      .order('created_at', { ascending: false })
    if (error) setError(error.message)
    else setTasks((data ?? []) as TaskTemplate[])
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchTasks()
    const channel = supabase
      .channel('tasks')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks' }, () => fetchTasks())
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [fetchTasks])

  return { tasks, loading, error, refresh: fetchTasks }
}
