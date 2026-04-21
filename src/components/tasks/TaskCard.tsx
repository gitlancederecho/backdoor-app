import type { DailyTask } from '@/lib/types'
import { formatTime } from '@/utils/date'

const STATUS_STYLES: Record<DailyTask['status'], string> = {
  pending: 'bg-status-pending',
  in_progress: 'bg-status-progress',
  completed: 'bg-status-done',
}

const STATUS_LABELS: Record<DailyTask['status'], string> = {
  pending: 'Pending',
  in_progress: 'In progress',
  completed: 'Done',
}

export function TaskCard({ task, onClick }: { task: DailyTask; onClick: () => void }) {
  const priority = task.task?.priority ?? 'normal'
  const priorityRing =
    priority === 'high' ? 'ring-1 ring-status-pending/50' : priority === 'low' ? 'opacity-80' : ''

  return (
    <button
      onClick={onClick}
      className={`card w-full text-left p-4 flex items-start gap-3 active:scale-[0.99] transition ${priorityRing} ${
        task.status === 'completed' ? 'opacity-60' : ''
      }`}
    >
      <span className={`mt-1.5 w-2.5 h-2.5 rounded-full shrink-0 ${STATUS_STYLES[task.status]}`} />
      <div className="flex-1 min-w-0">
        <div className="flex items-baseline gap-2 flex-wrap">
          <span className="font-medium">{task.task?.title ?? 'Task'}</span>
          {task.task?.title_ja && (
            <span className="font-jp text-sm text-neutral-400">{task.task.title_ja}</span>
          )}
        </div>
        <div className="flex items-center gap-2 mt-1.5 text-xs text-neutral-500">
          {task.assignee ? (
            <span className="flex items-center gap-1.5">
              <Avatar name={task.assignee.name} url={task.assignee.avatar_url} />
              {task.assignee.name}
            </span>
          ) : (
            <span className="text-neutral-600">Unassigned</span>
          )}
          <span>·</span>
          <span>{STATUS_LABELS[task.status]}</span>
          {task.completed_at && (
            <>
              <span>·</span>
              <span>{formatTime(task.completed_at)}</span>
            </>
          )}
        </div>
        {task.note && <p className="mt-2 text-xs text-neutral-400 line-clamp-2">"{task.note}"</p>}
      </div>
      {task.photo_url && (
        <img src={task.photo_url} alt="" className="w-12 h-12 rounded-lg object-cover border border-border" />
      )}
    </button>
  )
}

export function Avatar({ name, url, size = 20 }: { name: string; url: string | null; size?: number }) {
  const style = { width: size, height: size, fontSize: Math.round(size * 0.45) }
  if (url) {
    return <img src={url} alt={name} style={style} className="rounded-full object-cover" />
  }
  const initials = name.split(' ').map((s) => s[0]).filter(Boolean).slice(0, 2).join('').toUpperCase() || '?'
  return (
    <span
      style={style}
      className="rounded-full bg-bg-elevated border border-border flex items-center justify-center text-neutral-300 font-medium"
    >
      {initials}
    </span>
  )
}
