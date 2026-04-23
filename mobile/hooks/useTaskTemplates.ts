import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { TaskTemplate } from '@/lib/types'

export function useTaskTemplates() {
  const [tasks, setTasks] = useState<TaskTemplate[]>([])
  const [loading, setLoading] = useState(true)

  const fetchTasks = useCallback(async () => {
    const { data } = await supabase
      .from('tasks')
      .select('*')
      .eq('is_active', true)
      .order('created_at', { ascending: false })
    setTasks((data ?? []) as TaskTemplate[])
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchTasks()
    const ch = supabase
      .channel('tasks_mobile')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks' }, fetchTasks)
      .subscribe()
    return () => { supabase.removeChannel(ch) }
  }, [fetchTasks])

  return { tasks, loading, refresh: fetchTasks }
}
