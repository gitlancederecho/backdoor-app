import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { Staff } from '@/lib/types'

export function useStaff() {
  const [staff, setStaff] = useState<Staff[]>([])
  const [loading, setLoading] = useState(true)

  const fetchStaff = useCallback(async () => {
    const { data } = await supabase.from('staff').select('*').order('name')
    setStaff((data ?? []) as Staff[])
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchStaff()
    const ch = supabase
      .channel('staff_mobile')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'staff' }, fetchStaff)
      .subscribe()
    return () => { supabase.removeChannel(ch) }
  }, [fetchStaff])

  return { staff, loading, refresh: fetchStaff }
}
