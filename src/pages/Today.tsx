import { useDailyTasks } from '@/hooks/useDailyTasks'
import { TaskBoard } from '@/components/tasks/TaskBoard'

export default function Today() {
  const { tasks, loading, error } = useDailyTasks()
  return <TaskBoard tasks={tasks} loading={loading} error={error} />
}
