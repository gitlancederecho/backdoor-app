import { View, Text, Pressable, Image } from 'react-native'
import type { DailyTask } from '@/lib/types'
import { formatTime } from '@/utils/date'

const STATUS_COLORS = {
  pending: '#ef4444',
  in_progress: '#eab308',
  completed: '#22c55e',
} as const

export function TaskCard({ task, onPress }: { task: DailyTask; onPress: () => void }) {
  const isDone = task.status === 'completed'

  return (
    <Pressable
      onPress={onPress}
      className="bg-bg-card border border-[#2a2a2a] rounded-2xl p-4 flex-row items-start gap-3 active:opacity-75"
      style={{ opacity: isDone ? 0.65 : 1 }}
    >
      <View
        style={{ backgroundColor: STATUS_COLORS[task.status] }}
        className="w-2.5 h-2.5 rounded-full mt-1.5 shrink-0"
      />
      <View className="flex-1 min-w-0">
        <View className="flex-row items-baseline flex-wrap gap-x-2">
          <Text className="text-white font-medium text-base">{task.task?.title ?? 'Task'}</Text>
          {task.task?.title_ja && (
            <Text className="text-neutral-500 text-sm">{task.task.title_ja}</Text>
          )}
        </View>

        <View className="flex-row items-center gap-2 mt-1.5 flex-wrap">
          {task.assignee && (
            <Text className="text-neutral-500 text-xs">{task.assignee.name}</Text>
          )}
          {task.assignee && <Text className="text-neutral-700 text-xs">·</Text>}
          <Text className="text-neutral-500 text-xs capitalize">{task.status.replace('_', ' ')}</Text>
          {task.completed_at && (
            <>
              <Text className="text-neutral-700 text-xs">·</Text>
              <Text className="text-neutral-500 text-xs">{formatTime(task.completed_at)}</Text>
            </>
          )}
        </View>

        {task.note && (
          <Text className="text-neutral-400 text-xs mt-2" numberOfLines={2}>
            "{task.note}"
          </Text>
        )}
      </View>

      {task.photo_url && (
        <Image
          source={{ uri: task.photo_url }}
          className="w-14 h-14 rounded-xl border border-[#2a2a2a]"
        />
      )}
    </Pressable>
  )
}
