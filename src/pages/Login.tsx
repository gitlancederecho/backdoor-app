import { FormEvent, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'

export default function Login() {
  const { signIn, session } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [remember, setRemember] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (session) return <Navigate to="/" replace />

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setSubmitting(true)
    setError(null)
    const { error } = await signIn(email.trim(), password)
    setSubmitting(false)
    if (error) setError(error)
    // "remember" is cosmetic here — supabase-js persists sessions to localStorage by default.
    if (!remember) {
      // best-effort: clear storage on tab close
      window.addEventListener('beforeunload', () => localStorage.clear(), { once: true })
    }
  }

  return (
    <div className="min-h-full flex flex-col items-center justify-center px-6 pt-safe pb-safe">
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center mb-10">
          <div className="w-16 h-16 rounded-2xl bg-bg-card border border-border flex items-center justify-center mb-4">
            <span className="text-accent text-3xl font-bold">B</span>
          </div>
          <h1 className="text-2xl font-semibold tracking-tight">The Backdoor</h1>
          <p className="text-neutral-500 text-sm mt-1">Staff task board</p>
        </div>

        <form onSubmit={onSubmit} className="space-y-3">
          <input
            type="email"
            inputMode="email"
            autoComplete="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="input"
            required
          />
          <input
            type="password"
            autoComplete="current-password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="input"
            required
          />

          <label className="flex items-center gap-2 text-sm text-neutral-400 py-2 select-none">
            <input
              type="checkbox"
              checked={remember}
              onChange={(e) => setRemember(e.target.checked)}
              className="w-4 h-4 accent-accent"
            />
            Remember me
          </label>

          {error && (
            <div className="text-status-pending text-sm bg-status-pending/10 border border-status-pending/30 rounded-xl px-3 py-2">
              {error}
            </div>
          )}

          <button type="submit" className="btn-primary w-full" disabled={submitting}>
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
