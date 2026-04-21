export type Role = 'admin' | 'staff'
export type Category = 'opening' | 'closing' | 'bar' | 'cleaning' | 'weekly' | 'other'
export type Priority = 'low' | 'normal' | 'high'
export type TaskStatus = 'pending' | 'in_progress' | 'completed'
export type RecurrenceType = 'daily' | 'weekly' | 'monthly' | null

export interface Staff {
  id: string
  name: string
  role: Role
  email: string
  avatar_url: string | null
  is_active: boolean
  created_at: string
}

export interface TaskTemplate {
  id: string
  title: string
  title_ja: string | null
  category: Category
  assigned_to: string | null
  is_recurring: boolean
  recurrence_type: RecurrenceType
  recurrence_days: number[] | null
  priority: Priority
  created_by: string | null
  is_active: boolean
  created_at: string
}

export interface DailyTask {
  id: string
  task_id: string
  date: string // yyyy-mm-dd
  assigned_to: string | null
  status: TaskStatus
  completed_by: string | null
  completed_at: string | null
  note: string | null
  photo_url: string | null
  created_at: string
  // joined
  task?: TaskTemplate
  assignee?: Staff | null
  completer?: Staff | null
}

export const CATEGORY_LABELS: Record<Category, { en: string; ja: string }> = {
  opening: { en: 'Opening', ja: 'オープン' },
  closing: { en: 'Closing', ja: 'クローズ' },
  bar: { en: 'Bar', ja: 'バー' },
  cleaning: { en: 'Cleaning', ja: '清掃' },
  weekly: { en: 'Weekly', ja: '週次' },
  other: { en: 'Other', ja: 'その他' },
}

export const CATEGORY_ORDER: Category[] = ['opening', 'bar', 'cleaning', 'closing', 'weekly', 'other']
