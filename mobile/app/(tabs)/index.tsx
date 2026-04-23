import { SafeAreaView } from 'react-native-safe-area-context'
import { useDailyTasks } from '@/hooks/useDailyTasks'
import { TaskBoard } from '@/components/tasks/TaskBoard'

export default function Today() {
  const { tasks, loading, refreshing, pullRefresh } = useDailyTasks()
  return (
    <SafeAreaView className="flex-1 bg-bg" edges={['left', 'right']}>
      <TaskBoard tasks={tasks} loading={loading} refreshing={refreshing} onRefresh={pullRefresh} />
    </SafeAreaView>
  )
}
