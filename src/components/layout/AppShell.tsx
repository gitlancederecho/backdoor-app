import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'

export default function AppShell() {
  const { staff, isAdmin, signOut } = useAuth()

  return (
    <div className="h-full flex flex-col">
      <Header name={staff?.name ?? ''} onSignOut={signOut} />
      <main className="flex-1 overflow-y-auto pb-24">
        <Outlet />
      </main>
      <BottomNav isAdmin={isAdmin} />
    </div>
  )
}

function Header({ name, onSignOut }: { name: string; onSignOut: () => void }) {
  return (
    <header className="pt-safe sticky top-0 z-10 bg-bg/80 backdrop-blur border-b border-border">
      <div className="flex items-center justify-between px-4 py-3">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-bg-card border border-border flex items-center justify-center">
            <span className="text-accent font-bold">B</span>
          </div>
          <div className="leading-tight">
            <div className="font-semibold">The Backdoor</div>
            <div className="text-xs text-neutral-500">{name}</div>
          </div>
        </div>
        <button onClick={onSignOut} className="text-sm text-neutral-400 hover:text-neutral-200 px-2 py-1">
          Sign out
        </button>
      </div>
    </header>
  )
}

function BottomNav({ isAdmin }: { isAdmin: boolean }) {
  const item =
    'flex-1 flex flex-col items-center gap-1 py-2 text-xs text-neutral-500 aria-[current=page]:text-accent'
  return (
    <nav className="fixed bottom-0 left-0 right-0 z-10 bg-bg/95 backdrop-blur border-t border-border pb-safe">
      <div className="flex max-w-lg mx-auto">
        <NavLink to="/" end className={item}>
          <IconBoard /> Today
        </NavLink>
        <NavLink to="/mine" className={item}>
          <IconUser /> Mine
        </NavLink>
        {isAdmin && (
          <NavLink to="/admin" className={item}>
            <IconSettings /> Admin
          </NavLink>
        )}
      </div>
    </nav>
  )
}

function IconBoard() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M3 10h18M9 4v16" />
    </svg>
  )
}
function IconUser() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21c0-4.4 3.6-8 8-8s8 3.6 8 8" />
    </svg>
  )
}
function IconSettings() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3h.1a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8v.1a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
    </svg>
  )
}
