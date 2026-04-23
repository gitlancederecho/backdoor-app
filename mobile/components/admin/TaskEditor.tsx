import { useState } from 'react'
import { View, Text, TextInput, Pressable, ScrollView, ActivityIndicator, Alert } from 'react-native'
import { BottomSheet } from '@/components/ui/BottomSheet'
import { supabase } from '@/lib/supabase'
import { useStaff } from '@/hooks/useStaff'
import { useAuth } from '@/hooks/useAuth'
import type { Category, Priority, RecurrenceType, TaskTemplate } from '@/lib/types'

const CATEGORIES: Category[] = ['opening', 'bar', 'cleaning', 'closing', 'weekly', 'other']
const PRIORITIES: Priority[] = ['low', 'normal', 'high']
const WEEKDAYS = [
  { n: 1, label: 'M' }, { n: 2, label: 'T' }, { n: 3, label: 'W' },
  { n: 4, label: 'T' }, { n: 5, label: 'F' }, { n: 6, label: 'S' }, { n: 7, label: 'S' },
]

export function TaskEditor({ task, onClose }: { task: TaskTemplate | null; onClose: () => void }) {
  const { staff: allStaff } = useStaff()
  const { staff: me } = useAuth()
  const isNew = !task

  const [title, setTitle] = useState(task?.title ?? '')
  const [titleJa, setTitleJa] = useState(task?.title_ja ?? '')
  const [category, setCategory] = useState<Category>(task?.category ?? 'opening')
  const [assignedTo, setAssignedTo] = useState(task?.assigned_to ?? '')
  const [isRecurring, setIsRecurring] = useState(task?.is_recurring ?? true)
  const [recurrenceType, setRecurrenceType] = useState<RecurrenceType>(task?.recurrence_type ?? 'daily')
  const [days, setDays] = useState<number[]>(task?.recurrence_days ?? [])
  const [priority, setPriority] = useState<Priority>(task?.priority ?? 'normal')
  const [saving, setSaving] = useState(false)

  function toggleDay(n: number) {
    setDays((d) => d.includes(n) ? d.filter((x) => x !== n) : [...d, n].sort())
  }

  async function save() {
    if (!title.trim()) { Alert.alert('Required', 'Title is required'); return }
    setSaving(true)
    const payload = {
      title: title.trim(),
      title_ja: titleJa.trim() || null,
      category,
      assigned_to: assignedTo || null,
      is_recurring: isRecurring,
      recurrence_type: isRecurring ? recurrenceType : null,
      recurrence_days: isRecurring && recurrenceType !== 'daily' ? days : [],
      priority,
      is_active: true,
    }
    try {
      if (isNew) {
        const { error } = await supabase.from('tasks').insert({ ...payload, created_by: me?.id ?? null })
        if (error) throw error
      } else {
        const { error } = await supabase.from('tasks').update(payload).eq('id', task!.id)
        if (error) throw error
      }
      await supabase.rpc('generate_daily_tasks')
      onClose()
    } catch (e) {
      Alert.alert('Error', (e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <BottomSheet open onClose={onClose} title={isNew ? 'New task' : 'Edit task'}>
      <View className="gap-3">
        <Field label="Title (English)">
          <TextInput className="bg-bg border border-[#2a2a2a] rounded-xl px-4 py-3 text-white" value={title} onChangeText={setTitle} placeholderTextColor="#6b7280" placeholder="e.g. Wipe bar top" />
        </Field>
        <Field label="Title (日本語)">
          <TextInput className="bg-bg border border-[#2a2a2a] rounded-xl px-4 py-3 text-white" value={titleJa} onChangeText={setTitleJa} placeholderTextColor="#6b7280" placeholder="e.g. バーカウンターを拭く" />
        </Field>

        <Field label="Category">
          <ScrollView horizontal showsHorizontalScrollIndicator={false} className="-mx-1">
            {CATEGORIES.map((c) => (
              <Pressable key={c} onPress={() => setCategory(c)} className={`mx-1 px-3 py-2 rounded-xl border ${category === c ? 'bg-accent border-accent' : 'border-[#2a2a2a]'}`}>
                <Text className={category === c ? 'text-black font-medium capitalize' : 'text-neutral-400 capitalize'}>{c}</Text>
              </Pressable>
            ))}
          </ScrollView>
        </Field>

        <Field label="Priority">
          <View className="flex-row gap-2">
            {PRIORITIES.map((p) => (
              <Pressable key={p} onPress={() => setPriority(p)} className={`flex-1 py-3 rounded-xl border items-center ${priority === p ? 'bg-accent border-accent' : 'border-[#2a2a2a]'}`}>
                <Text className={priority === p ? 'text-black font-medium capitalize' : 'text-neutral-400 capitalize'}>{p}</Text>
              </Pressable>
            ))}
          </View>
        </Field>

        <Field label="Assign to">
          <ScrollView horizontal showsHorizontalScrollIndicator={false} className="-mx-1">
            <Pressable onPress={() => setAssignedTo('')} className={`mx-1 px-3 py-2 rounded-xl border ${!assignedTo ? 'bg-accent border-accent' : 'border-[#2a2a2a]'}`}>
              <Text className={!assignedTo ? 'text-black font-medium' : 'text-neutral-400'}>Anyone</Text>
            </Pressable>
            {allStaff.filter((s) => s.is_active).map((s) => (
              <Pressable key={s.id} onPress={() => setAssignedTo(s.id)} className={`mx-1 px-3 py-2 rounded-xl border ${assignedTo === s.id ? 'bg-accent border-accent' : 'border-[#2a2a2a]'}`}>
                <Text className={assignedTo === s.id ? 'text-black font-medium' : 'text-neutral-400'}>{s.name}</Text>
              </Pressable>
            ))}
          </ScrollView>
        </Field>

        {/* Recurring toggle */}
        <View className="flex-row items-center justify-between py-1">
          <Text className="text-neutral-300">Recurring</Text>
          <Pressable
            onPress={() => setIsRecurring(!isRecurring)}
            className={`w-12 h-7 rounded-full transition ${isRecurring ? 'bg-accent' : 'bg-bg-elevated'}`}
          >
            <View className={`w-5 h-5 rounded-full bg-white m-1 ${isRecurring ? 'ml-6' : 'ml-1'}`} />
          </Pressable>
        </View>

        {isRecurring && (
          <>
            <Field label="Repeats">
              <View className="flex-row gap-2">
                {(['daily', 'weekly', 'monthly'] as RecurrenceType[]).map((r) => (
                  <Pressable key={r!} onPress={() => setRecurrenceType(r)} className={`flex-1 py-3 rounded-xl border items-center ${recurrenceType === r ? 'bg-accent border-accent' : 'border-[#2a2a2a]'}`}>
                    <Text className={recurrenceType === r ? 'text-black font-medium capitalize' : 'text-neutral-400 capitalize'}>{r}</Text>
                  </Pressable>
                ))}
              </View>
            </Field>

            {recurrenceType === 'weekly' && (
              <Field label="Days">
                <View className="flex-row gap-1.5">
                  {WEEKDAYS.map((d) => (
                    <Pressable key={d.n} onPress={() => toggleDay(d.n)} className={`flex-1 py-2.5 rounded-xl border items-center ${days.includes(d.n) ? 'bg-accent border-accent' : 'border-[#2a2a2a]'}`}>
                      <Text className={days.includes(d.n) ? 'text-black font-medium text-xs' : 'text-neutral-400 text-xs'}>{d.label}</Text>
                    </Pressable>
                  ))}
                </View>
              </Field>
            )}
          </>
        )}

        <View className="flex-row gap-2 mt-2">
          <Pressable onPress={onClose} className="flex-1 bg-bg-elevated border border-[#2a2a2a] rounded-2xl py-4 items-center">
            <Text className="text-neutral-300 font-medium">Cancel</Text>
          </Pressable>
          <Pressable onPress={save} disabled={saving} className="flex-1 bg-accent rounded-2xl py-4 items-center">
            {saving ? <ActivityIndicator color="#000" /> : <Text className="text-black font-semibold">{isNew ? 'Create' : 'Save'}</Text>}
          </Pressable>
        </View>
      </View>
    </BottomSheet>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View>
      <Text className="text-neutral-500 text-xs mb-1.5">{label}</Text>
      {children}
    </View>
  )
}
