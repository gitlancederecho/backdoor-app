import { useState } from 'react'
import { Modal } from '@/components/ui/Modal'
import { useAuth } from '@/hooks/useAuth'
import { updateDailyTask } from '@/hooks/useDailyTasks'
import { PHOTO_BUCKET, supabase } from '@/lib/supabase'
import type { DailyTask } from '@/lib/types'
import { Avatar } from './TaskCard'
import { formatTime } from '@/utils/date'

export function TaskCompletion({ task, onClose }: { task: DailyTask; onClose: () => void }) {
  const { staff } = useAuth()
  const [note, setNote] = useState(task.note ?? '')
  const [photoFile, setPhotoFile] = useState<File | null>(null)
  const [photoPreview, setPhotoPreview] = useState<string | null>(task.photo_url)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const alreadyDone = task.status === 'completed'
  const canUndo = alreadyDone && staff && (staff.role === 'admin' || task.completed_by === staff.id)

  function onPickPhoto(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setPhotoFile(file)
    setPhotoPreview(URL.createObjectURL(file))
  }

  async function uploadPhoto(): Promise<string | null> {
    if (!photoFile) return task.photo_url
    const ext = photoFile.name.split('.').pop() ?? 'jpg'
    const path = `${task.date}/${task.id}-${Date.now()}.${ext}`
    const { error } = await supabase.storage.from(PHOTO_BUCKET).upload(path, photoFile, {
      cacheControl: '3600',
      upsert: false,
      contentType: photoFile.type,
    })
    if (error) throw error
    const { data } = supabase.storage.from(PHOTO_BUCKET).getPublicUrl(path)
    return data.publicUrl
  }

  async function startTask() {
    if (!staff) return
    setSaving(true)
    setError(null)
    try {
      await updateDailyTask(task.id, {
        status: 'in_progress',
        // claim the task if unassigned
        assigned_to: task.assigned_to ?? staff.id,
      })
      onClose()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  async function completeTask() {
    if (!staff) return
    setSaving(true)
    setError(null)
    try {
      const photo_url = await uploadPhoto()
      await updateDailyTask(task.id, {
        status: 'completed',
        completed_by: staff.id,
        completed_at: new Date().toISOString(),
        note: note.trim() || null,
        photo_url,
        assigned_to: task.assigned_to ?? staff.id,
      })
      onClose()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  async function undoComplete() {
    setSaving(true)
    setError(null)
    try {
      await updateDailyTask(task.id, {
        status: 'in_progress',
        completed_by: null,
        completed_at: null,
      })
      onClose()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open onClose={onClose} title={task.task?.title}>
      {task.task?.title_ja && (
        <p className="font-jp text-neutral-400 -mt-2 mb-3">{task.task.title_ja}</p>
      )}

      <div className="text-sm text-neutral-400 mb-4 space-y-1">
        <div>
          Assigned to:{' '}
          {task.assignee ? (
            <span className="inline-flex items-center gap-1.5">
              <Avatar name={task.assignee.name} url={task.assignee.avatar_url} /> {task.assignee.name}
            </span>
          ) : (
            <span className="text-neutral-600">Unassigned — will be claimed by you</span>
          )}
        </div>
        {alreadyDone && task.completer && (
          <div>
            Completed by <span className="text-neutral-200">{task.completer.name}</span>{' '}
            at {formatTime(task.completed_at)}
          </div>
        )}
      </div>

      <div className="space-y-3">
        <div>
          <label className="text-xs text-neutral-500 mb-1 block">Note (optional)</label>
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="e.g. ran out of limes"
            className="input min-h-[80px] resize-y"
            disabled={alreadyDone && !canUndo}
          />
        </div>

        <div>
          <label className="text-xs text-neutral-500 mb-1 block">Photo (optional)</label>
          {photoPreview ? (
            <div className="relative w-full">
              <img src={photoPreview} alt="" className="w-full max-h-64 object-cover rounded-xl border border-border" />
              {!alreadyDone && (
                <button
                  onClick={() => {
                    setPhotoFile(null)
                    setPhotoPreview(null)
                  }}
                  className="absolute top-2 right-2 bg-black/60 text-white text-xs rounded-full px-2 py-1"
                >
                  Remove
                </button>
              )}
            </div>
          ) : (
            <label className="btn-secondary w-full cursor-pointer">
              <input
                type="file"
                accept="image/*"
                capture="environment"
                className="hidden"
                onChange={onPickPhoto}
                disabled={alreadyDone && !canUndo}
              />
              📷 Take / upload photo
            </label>
          )}
        </div>

        {error && (
          <div className="text-sm text-status-pending bg-status-pending/10 border border-status-pending/30 rounded-xl px-3 py-2">
            {error}
          </div>
        )}

        <div className="flex gap-2 pt-2">
          {alreadyDone ? (
            canUndo && (
              <button onClick={undoComplete} className="btn-secondary flex-1" disabled={saving}>
                Undo complete
              </button>
            )
          ) : (
            <>
              {task.status === 'pending' && (
                <button onClick={startTask} className="btn-secondary flex-1" disabled={saving}>
                  Start
                </button>
              )}
              <button onClick={completeTask} className="btn-primary flex-1" disabled={saving}>
                {saving ? 'Saving…' : 'Mark done'}
              </button>
            </>
          )}
        </div>
      </div>
    </Modal>
  )
}
