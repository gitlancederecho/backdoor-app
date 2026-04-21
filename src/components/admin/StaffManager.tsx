import { useState } from 'react'
import { useStaff } from '@/hooks/useStaff'
import { supabase } from '@/lib/supabase'
import type { Role, Staff } from '@/lib/types'
import { Avatar } from '@/components/tasks/TaskCard'
import { Modal } from '@/components/ui/Modal'

export function StaffManager() {
  const { staff, loading } = useStaff()
  const [editing, setEditing] = useState<Staff | null>(null)

  async function toggleActive(s: Staff) {
    await supabase.from('staff').update({ is_active: !s.is_active }).eq('id', s.id)
  }

  async function changeRole(s: Staff, role: Role) {
    await supabase.from('staff').update({ role }).eq('id', s.id)
  }

  return (
    <div>
      <p className="text-sm text-neutral-500 mb-3">
        New staff sign up with their email/password on the login screen — they appear here automatically. Set their role to admin to grant access to this panel.
      </p>

      {loading && <div className="text-neutral-500 text-sm">Loading…</div>}

      <div className="space-y-2">
        {staff.map((s) => (
          <div key={s.id} className="card p-3 flex items-center gap-3">
            <Avatar name={s.name} url={s.avatar_url} size={40} />
            <div className="flex-1 min-w-0">
              <div className="font-medium truncate">{s.name}</div>
              <div className="text-xs text-neutral-500 truncate">{s.email}</div>
            </div>
            <select
              value={s.role}
              onChange={(e) => changeRole(s, e.target.value as Role)}
              className="bg-bg-elevated border border-border rounded-lg px-2 py-1 text-sm"
            >
              <option value="staff">staff</option>
              <option value="admin">admin</option>
            </select>
            <button
              onClick={() => toggleActive(s)}
              className={`text-xs px-2 py-1 rounded-lg border ${
                s.is_active ? 'border-border text-neutral-400' : 'border-status-pending/50 text-status-pending'
              }`}
            >
              {s.is_active ? 'Active' : 'Inactive'}
            </button>
            <button onClick={() => setEditing(s)} className="text-sm text-accent px-2">
              Edit
            </button>
          </div>
        ))}
      </div>

      {editing && <EditStaff staff={editing} onClose={() => setEditing(null)} />}
    </div>
  )
}

function EditStaff({ staff, onClose }: { staff: Staff; onClose: () => void }) {
  const [name, setName] = useState(staff.name)
  const [avatar, setAvatar] = useState(staff.avatar_url ?? '')
  const [saving, setSaving] = useState(false)

  async function save() {
    setSaving(true)
    await supabase.from('staff').update({ name, avatar_url: avatar || null }).eq('id', staff.id)
    setSaving(false)
    onClose()
  }

  return (
    <Modal open onClose={onClose} title="Edit staff">
      <div className="space-y-3">
        <div>
          <label className="text-xs text-neutral-500 mb-1 block">Name</label>
          <input className="input" value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div>
          <label className="text-xs text-neutral-500 mb-1 block">Avatar URL (optional)</label>
          <input className="input" value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="https://…" />
        </div>
        <div className="flex gap-2 pt-1">
          <button className="btn-secondary flex-1" onClick={onClose}>Cancel</button>
          <button className="btn-primary flex-1" onClick={save} disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </Modal>
  )
}
