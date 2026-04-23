import { useMemo, useState } from 'react'
import { View, Text, Pressable, SectionList, Alert, ActivityIndicator } from 'react-native'
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context'
import { useDailyTasks } from '@/hooks/useDailyTasks'
import { useStaff } from '@/hooks/useStaff'
import { useTaskTemplates } from '@/hooks/useTaskTemplates'
import { TaskEditor } from '@/components/admin/TaskEditor'
import { supabase } from '@/lib/supabase'
import type { TaskTemplate } from '@/lib/types'

type Tab = 'overview' | 'tasks' | 'staff'

export default function Admin() {
  const [tab, setTab] = useState<Tab>('overview')
  const insets = useSafeAreaInsets()

  return (
    <SafeAreaView className="flex-1 bg-bg" edges={['left', 'right']}>
      {/* Header */}
      <View style={{ paddingTop: insets.top + 8 }} className="px-4 pb-3">
        <Text className="text-white text-2xl font-bold mb-3">Admin</Text>
        <View className="flex-row gap-2">
          {(['overview', 'tasks', 'staff'] as Tab[]).map((t) => (
            <Pressable
              key={t}
              onPress={() => setTab(t)}
              className={`px-4 py-2 rounded-full border capitalize ${tab === t ? 'bg-accent border-accent' : 'border-[#2a2a2a]'}`}
            >
              <Text className={tab === t ? 'text-black font-medium capitalize' : 'text-neutral-400 capitalize'}>{t}</Text>
            </Pressable>
          ))}
        </View>
      </View>

      {tab === 'overview' && <OverviewTab />}
      {tab === 'tasks' && <TasksTab />}
      {tab === 'staff' && <StaffTab />}
    </SafeAreaView>
  )
}

function OverviewTab() {
  const { tasks: daily, loading } = useDailyTasks()
  const { staff } = useStaff()
  const insets = useSafeAreaInsets()

  const total = daily.length
  const done = daily.filter((t) => t.status === 'completed').length
  const pct = total === 0 ? 0 : Math.round((done / total) * 100)

  const perStaff = useMemo(() => {
    return staff
      .filter((s) => s.is_active)
      .map((s) => {
        const assigned = daily.filter((t) => t.assigned_to === s.id)
        const doneCount = assigned.filter((t) => t.status === 'completed').length
        return {
          id: s.id,
          name: s.name,
          assigned: assigned.length,
          done: doneCount,
          rate: assigned.length === 0 ? 0 : Math.round((doneCount / assigned.length) * 100),
        }
      })
      .sort((a, b) => b.rate - a.rate)
  }, [staff, daily])

  if (loading) return <View className="flex-1 items-center justify-center"><ActivityIndicator color="#e8b84b" /></View>

  return (
    <SectionList
      sections={[{ title: 'per-staff', data: perStaff }]}
      keyExtractor={(item) => item.id}
      contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: insets.bottom + 90 }}
      ListHeaderComponent={
        <>
          {/* Stats */}
          <View className="flex-row gap-2 mb-4">
            <StatCard label="Total" value={total} />
            <StatCard label="Done" value={`${done} · ${pct}%`} color="#22c55e" />
            <StatCard label="Open" value={total - done} color={total - done > 0 ? '#ef4444' : undefined} />
          </View>
          <Text className="text-neutral-500 text-xs uppercase tracking-widest mb-2">Per staff · today</Text>
        </>
      }
      renderItem={({ item }) => (
        <View className="flex-row items-center bg-bg-card border border-[#2a2a2a] rounded-2xl px-4 py-3 mb-2">
          <View className="w-9 h-9 rounded-full bg-bg-elevated border border-[#2a2a2a] items-center justify-center mr-3">
            <Text className="text-neutral-300 text-sm font-medium">
              {item.name.split(' ').map((s: string) => s[0]).slice(0, 2).join('').toUpperCase()}
            </Text>
          </View>
          <View className="flex-1">
            <Text className="text-white font-medium">{item.name}</Text>
            <Text className="text-neutral-500 text-xs">{item.done}/{item.assigned} · {item.rate}%</Text>
          </View>
          <View className="w-16 h-1.5 bg-bg-elevated rounded-full overflow-hidden">
            <View className="h-full bg-accent rounded-full" style={{ width: `${item.rate}%` }} />
          </View>
        </View>
      )}
      renderSectionHeader={() => null}
    />
  )
}

function StatCard({ label, value, color }: { label: string; value: string | number; color?: string }) {
  return (
    <View className="flex-1 bg-bg-card border border-[#2a2a2a] rounded-2xl p-3">
      <Text className="text-neutral-500 text-xs">{label}</Text>
      <Text className="text-xl font-bold mt-1" style={{ color: color ?? '#fff' }}>{value}</Text>
    </View>
  )
}

function TasksTab() {
  const { tasks, loading } = useTaskTemplates()
  const [editing, setEditing] = useState<TaskTemplate | 'new' | null>(null)
  const insets = useSafeAreaInsets()

  async function deleteTask(id: string) {
    Alert.alert('Delete task', 'Remove this task from future days?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete', style: 'destructive',
        onPress: () => supabase.from('tasks').update({ is_active: false }).eq('id', id),
      },
    ])
  }

  if (loading) return <View className="flex-1 items-center justify-center"><ActivityIndicator color="#e8b84b" /></View>

  return (
    <View className="flex-1">
      <SectionList
        sections={[{ title: 'tasks', data: tasks }]}
        keyExtractor={(item) => item.id}
        contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: insets.bottom + 90 }}
        ListHeaderComponent={
          <Pressable onPress={() => setEditing('new')} className="bg-accent rounded-2xl py-4 items-center mb-3">
            <Text className="text-black font-semibold">+ New task</Text>
          </Pressable>
        }
        renderSectionHeader={() => null}
        renderItem={({ item }) => (
          <View className="bg-bg-card border border-[#2a2a2a] rounded-2xl px-4 py-3 mb-2 flex-row items-start">
            <View className="flex-1 mr-3">
              <View className="flex-row flex-wrap gap-x-2 items-baseline">
                <Text className="text-white font-medium">{item.title}</Text>
                {item.title_ja && <Text className="text-neutral-500 text-sm">{item.title_ja}</Text>}
              </View>
              <Text className="text-neutral-600 text-xs mt-1 capitalize">
                {item.category} · {item.is_recurring ? item.recurrence_type : 'one-off'}
                {item.priority !== 'normal' ? ` · ${item.priority}` : ''}
              </Text>
            </View>
            <View className="flex-row gap-3">
              <Pressable onPress={() => setEditing(item)}>
                <Text className="text-accent text-sm">Edit</Text>
              </Pressable>
              <Pressable onPress={() => deleteTask(item.id)}>
                <Text className="text-red-400 text-sm">Del</Text>
              </Pressable>
            </View>
          </View>
        )}
      />

      {editing && (
        <TaskEditor task={editing === 'new' ? null : editing} onClose={() => setEditing(null)} />
      )}
    </View>
  )
}

function StaffTab() {
  const { staff, loading } = useStaff()
  const insets = useSafeAreaInsets()

  async function toggleRole(id: string, currentRole: string) {
    const newRole = currentRole === 'admin' ? 'staff' : 'admin'
    Alert.alert('Change role', `Set as ${newRole}?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Confirm', onPress: () => supabase.from('staff').update({ role: newRole }).eq('id', id) },
    ])
  }

  async function toggleActive(id: string, isActive: boolean) {
    await supabase.from('staff').update({ is_active: !isActive }).eq('id', id)
  }

  if (loading) return <View className="flex-1 items-center justify-center"><ActivityIndicator color="#e8b84b" /></View>

  return (
    <SectionList
      sections={[{ title: 'staff', data: staff }]}
      keyExtractor={(item) => item.id}
      contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: insets.bottom + 90 }}
      ListHeaderComponent={
        <Text className="text-neutral-500 text-xs mb-3">
          Staff sign up via the login screen — they appear here automatically.
        </Text>
      }
      renderSectionHeader={() => null}
      renderItem={({ item }) => (
        <View className="bg-bg-card border border-[#2a2a2a] rounded-2xl px-4 py-3 mb-2 flex-row items-center">
          <View className="w-10 h-10 rounded-full bg-bg-elevated border border-[#2a2a2a] items-center justify-center mr-3">
            <Text className="text-neutral-300 text-sm font-medium">
              {item.name.split(' ').map((s: string) => s[0]).slice(0, 2).join('').toUpperCase()}
            </Text>
          </View>
          <View className="flex-1">
            <Text className="text-white font-medium">{item.name}</Text>
            <Text className="text-neutral-500 text-xs" numberOfLines={1}>{item.email}</Text>
          </View>
          <View className="flex-row gap-2 ml-2">
            <Pressable
              onPress={() => toggleRole(item.id, item.role)}
              className={`px-2.5 py-1.5 rounded-lg border ${item.role === 'admin' ? 'border-accent' : 'border-[#2a2a2a]'}`}
            >
              <Text className={item.role === 'admin' ? 'text-accent text-xs' : 'text-neutral-500 text-xs'}>{item.role}</Text>
            </Pressable>
            <Pressable
              onPress={() => toggleActive(item.id, item.is_active)}
              className={`px-2.5 py-1.5 rounded-lg border ${item.is_active ? 'border-[#2a2a2a]' : 'border-red-500/50'}`}
            >
              <Text className={item.is_active ? 'text-neutral-500 text-xs' : 'text-red-400 text-xs'}>
                {item.is_active ? 'Active' : 'Off'}
              </Text>
            </Pressable>
          </View>
        </View>
      )}
    />
  )
}
