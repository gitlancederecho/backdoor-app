export function todayIso(): string {
  // Local-date yyyy-mm-dd (avoids UTC off-by-one for Asia timezones)
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

export function formatDate(iso: string): string {
  const d = new Date(iso + 'T00:00:00')
  return d.toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  })
}

export function formatTime(iso: string | null): string {
  if (!iso) return ''
  return new Date(iso).toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  })
}

// 0 = Sunday in JS; schema uses 1=Mon..7=Sun. Support both representations.
export function jsWeekdayToIso(weekday: number): number {
  return weekday === 0 ? 7 : weekday
}
