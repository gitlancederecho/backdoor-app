import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { Staff } from '@/lib/types'

export function useStaff() {
  const [staff, setStaff] = useState<Staff[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchStaff = useCallback(async () => {
    setError(null)
    const { data, error } = await supabase.from('staff').select('*').order('name')
    if (error) setError(error.message)
    else setStaff((data ?? []) as Staff[])
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchStaff()
    const channel = supabase
      .channel('staff')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'staff' }, () => fetchStaff())
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [fetchStaff])

  return { staff, loading, error, refresh: fetchStaff }
}
