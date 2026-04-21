import { useDailyTasks } from '@/hooks/useDailyTasks'
import { TaskBoard } from '@/components/tasks/TaskBoard'
import { useAuth } from '@/hooks/useAuth'

export default function MyTasks() {
  const { tasks, loading, error } = useDailyTasks()
  const { staff } = useAuth()
  return (
    <TaskBoard
      tasks={tasks}
      loading={loading}
      error={error}
      filterMine
      currentStaffId={staff?.id}
    />
  )
}
