import { createContext, useContext, useEffect, useState, ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import type { Staff } from '@/lib/types'

interface AuthContextValue {
  session: Session | null
  staff: Staff | null
  loading: boolean
  signIn: (email: string, password: string) => Promise<{ error: string | null }>
  signOut: () => Promise<void>
  isAdmin: boolean
  refreshStaff: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [staff, setStaff] = useState<Staff | null>(null)
  const [loading, setLoading] = useState(true)

  async function loadStaff(userId: string) {
    const { data } = await supabase
      .from('staff')
      .select('*')
      .eq('auth_user_id', userId)
      .maybeSingle()
    setStaff((data as Staff) ?? null)
  }

  useEffect(() => {
    let mounted = true

    supabase.auth.getSession().then(async ({ data }) => {
      if (!mounted) return
      setSession(data.session)
      if (data.session?.user) {
        await loadStaff(data.session.user.id)
      }
      setLoading(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange(async (_event, newSession) => {
      setSession(newSession)
      if (newSession?.user) {
        await loadStaff(newSession.user.id)
      } else {
        setStaff(null)
      }
    })

    return () => {
      mounted = false
      sub.subscription.unsubscribe()
    }
  }, [])

  async function signIn(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error: error?.message ?? null }
  }

  async function signOut() {
    await supabase.auth.signOut()
  }

  async function refreshStaff() {
    if (session?.user) await loadStaff(session.user.id)
  }

  const value: AuthContextValue = {
    session,
    staff,
    loading,
    signIn,
    signOut,
    isAdmin: staff?.role === 'admin',
    refreshStaff,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider')
  return ctx
}
