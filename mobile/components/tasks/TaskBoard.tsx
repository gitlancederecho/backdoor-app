import { useMemo, useState } from 'react'
import { View, Text, SectionList, RefreshControl } from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { CATEGORY_LABELS, CATEGORY_ORDER, Category, DailyTask } from '@/lib/types'
import { TaskCard } from './TaskCard'
import { TaskCompletion } from './TaskCompletion'
import { formatDate, todayIso } from '@/utils/date'
import { useAuth } from '@/hooks/useAuth'

type Section = { title: string; titleJa: string; done: number; total: number; data: DailyTask[] }

export function TaskBoard({
  tasks,
  loading,
  refreshing,
  onRefresh,
  filterMine,
}: {
  tasks: DailyTask[]
  loading: boolean
  refreshing: boolean
  onRefresh: () => void
  filterMine?: boolean
}) {
  const { staff } = useAuth()
  const insets = useSafeAreaInsets()
  const [selected, setSelected] = useState<DailyTask | null>(null)

  const visible = useMemo(() => {
    if (!filterMine || !staff) return tasks
    return tasks.filter((t) => t.assigned_to === staff.id)
  }, [tasks, filterMine, staff])

  const sections = useMemo<Section[]>(() => {
    return CATEGORY_ORDER
      .map((cat) => {
        const list = visible.filter((t) => (t.task?.category ?? 'other') === cat)
        if (list.length === 0) return null
        return {
          title: CATEGORY_LABELS[cat as Category].en,
          titleJa: CATEGORY_LABELS[cat as Category].ja,
          done: list.filter((t) => t.status === 'completed').length,
          total: list.length,
          data: list,
        }
      })
      .filter(Boolean) as Section[]
  }, [visible])

  const total = visible.length
  const done = visible.filter((t) => t.status === 'completed').length

  return (
    <>
      <SectionList
        sections={sections}
        keyExtractor={(item) => item.id}
        contentContainerStyle={{
          paddingTop: insets.top + 8,
          paddingBottom: insets.bottom + 90,
          paddingHorizontal: 16,
        }}
        renderItem={({ item }) => (
          <View className="mb-2">
            <TaskCard task={item} onPress={() => setSelected(item)} />
          </View>
        )}
        renderSectionHeader={({ section }) => (
          <View className="flex-row items-baseline gap-2 mb-2 mt-4">
            <Text className="text-neutral-500 text-xs uppercase tracking-widest">{section.title}</Text>
            <Text className="text-neutral-500 text-xs">{section.titleJa}</Text>
            <Text className="text-neutral-700 text-xs ml-auto">{section.done}/{section.total}</Text>
          </View>
        )}
        ListHeaderComponent={
          <View className="mb-2">
            <Text className="text-white text-2xl font-bold">{formatDate(todayIso())}</Text>
            <Text className="text-neutral-500 text-sm mt-0.5">
              {done}/{total} done{total > 0 ? ` · ${Math.round((done / total) * 100)}%` : ''}
            </Text>
          </View>
        }
        ListEmptyComponent={
          !loading ? (
            <View className="bg-bg-card border border-[#2a2a2a] rounded-2xl p-6 items-center mt-4">
              <Text className="text-neutral-500 text-center">
                {filterMine ? 'No tasks assigned to you today.' : 'No tasks today. An admin can add recurring tasks.'}
              </Text>
            </View>
          ) : null
        }
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor="#e8b84b"
          />
        }
        stickySectionHeadersEnabled={false}
      />

      {selected && <TaskCompletion task={selected} onClose={() => setSelected(null)} />}
    </>
  )
}
