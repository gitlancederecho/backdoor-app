import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { ReactNode } from 'react'

export function ProtectedRoute({ children, adminOnly = false }: { children: ReactNode; adminOnly?: boolean }) {
  const { session, staff, loading, isAdmin } = useAuth()
  const location = useLocation()

  if (loading) {
    return (
      <div className="h-full flex items-center justify-center text-neutral-400">
        Loading…
      </div>
    )
  }

  if (!session) {
    return <Navigate to="/login" replace state={{ from: location }} />
  }

  if (adminOnly && !isAdmin) {
    return <Navigate to="/" replace />
  }

  if (!staff) {
    return (
      <div className="h-full flex flex-col items-center justify-center p-6 text-center text-neutral-400 gap-2">
        <p>Your account has no staff profile yet.</p>
        <p className="text-sm">Ask an admin to set you up.</p>
      </div>
    )
  }

  return <>{children}</>
}
