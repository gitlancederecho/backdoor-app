import { useState } from 'react'
import { View, Text, TextInput, Pressable, Image, ActivityIndicator, Alert } from 'react-native'
import * as ImagePicker from 'expo-image-picker'
import { BottomSheet } from '@/components/ui/BottomSheet'
import { useAuth } from '@/hooks/useAuth'
import { updateDailyTask } from '@/hooks/useDailyTasks'
import { supabase, PHOTO_BUCKET } from '@/lib/supabase'
import type { DailyTask } from '@/lib/types'
import { formatTime } from '@/utils/date'

export function TaskCompletion({ task, onClose }: { task: DailyTask; onClose: () => void }) {
  const { staff } = useAuth()
  const [note, setNote] = useState(task.note ?? '')
  const [photoUri, setPhotoUri] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const isDone = task.status === 'completed'
  const canUndo = isDone && (staff?.role === 'admin' || task.completed_by === staff?.id)

  async function pickPhoto() {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.7,
      allowsEditing: true,
    })
    if (!result.canceled) setPhotoUri(result.assets[0].uri)
  }

  async function takePhoto() {
    const perm = await ImagePicker.requestCameraPermissionsAsync()
    if (!perm.granted) {
      Alert.alert('Permission needed', 'Camera access is required to take photos.')
      return
    }
    const result = await ImagePicker.launchCameraAsync({ quality: 0.7, allowsEditing: true })
    if (!result.canceled) setPhotoUri(result.assets[0].uri)
  }

  async function uploadPhoto(): Promise<string | null> {
    if (!photoUri) return task.photo_url
    const ext = photoUri.split('.').pop() ?? 'jpg'
    const path = `${task.date}/${task.id}-${Date.now()}.${ext}`
    const response = await fetch(photoUri)
    const blob = await response.blob()
    const { error } = await supabase.storage.from(PHOTO_BUCKET).upload(path, blob, {
      contentType: `image/${ext}`,
      upsert: false,
    })
    if (error) throw error
    return supabase.storage.from(PHOTO_BUCKET).getPublicUrl(path).data.publicUrl
  }

  async function startTask() {
    if (!staff) return
    setSaving(true)
    try {
      await updateDailyTask(task.id, {
        status: 'in_progress',
        assigned_to: task.assigned_to ?? staff.id,
      })
      onClose()
    } catch (e) {
      Alert.alert('Error', (e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  async function completeTask() {
    if (!staff) return
    setSaving(true)
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
      Alert.alert('Error', (e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  async function undoComplete() {
    setSaving(true)
    try {
      await updateDailyTask(task.id, { status: 'in_progress', completed_by: null, completed_at: null })
      onClose()
    } catch (e) {
      Alert.alert('Error', (e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <BottomSheet open onClose={onClose} title={task.task?.title}>
      {task.task?.title_ja && (
        <Text className="text-neutral-500 text-sm -mt-1 mb-3">{task.task.title_ja}</Text>
      )}

      {/* Meta */}
      <View className="mb-4 gap-1">
        <Text className="text-neutral-500 text-sm">
          Assigned: <Text className="text-neutral-300">{task.assignee?.name ?? 'Unassigned'}</Text>
        </Text>
        {isDone && task.completer && (
          <Text className="text-neutral-500 text-sm">
            Done by <Text className="text-neutral-300">{task.completer.name}</Text>
            {task.completed_at ? ` · ${formatTime(task.completed_at)}` : ''}
          </Text>
        )}
      </View>

      {/* Note */}
      <Text className="text-neutral-500 text-xs mb-1">Note (optional)</Text>
      <TextInput
        className="bg-bg border border-[#2a2a2a] rounded-xl px-4 py-3 text-white text-sm mb-3"
        placeholder="e.g. ran out of limes"
        placeholderTextColor="#6b7280"
        value={note}
        onChangeText={setNote}
        multiline
        numberOfLines={3}
        editable={!isDone}
      />

      {/* Photo */}
      <Text className="text-neutral-500 text-xs mb-1">Photo (optional)</Text>
      {photoUri || task.photo_url ? (
        <View className="mb-3 relative">
          <Image
            source={{ uri: photoUri ?? task.photo_url! }}
            className="w-full h-48 rounded-xl border border-[#2a2a2a]"
            resizeMode="cover"
          />
          {!isDone && (
            <Pressable
              onPress={() => setPhotoUri(null)}
              className="absolute top-2 right-2 bg-black/60 rounded-full px-3 py-1"
            >
              <Text className="text-white text-xs">Remove</Text>
            </Pressable>
          )}
        </View>
      ) : (
        !isDone && (
          <View className="flex-row gap-2 mb-3">
            <Pressable
              onPress={takePhoto}
              className="flex-1 bg-bg-elevated border border-[#2a2a2a] rounded-xl py-3 items-center"
            >
              <Text className="text-neutral-300 text-sm">📷 Camera</Text>
            </Pressable>
            <Pressable
              onPress={pickPhoto}
              className="flex-1 bg-bg-elevated border border-[#2a2a2a] rounded-xl py-3 items-center"
            >
              <Text className="text-neutral-300 text-sm">🖼 Library</Text>
            </Pressable>
          </View>
        )
      )}

      {/* Actions */}
      <View className="flex-row gap-2 mt-2">
        {isDone ? (
          canUndo && (
            <Pressable
              onPress={undoComplete}
              disabled={saving}
              className="flex-1 bg-bg-elevated border border-[#2a2a2a] rounded-2xl py-4 items-center"
            >
              <Text className="text-neutral-300 font-medium">Undo</Text>
            </Pressable>
          )
        ) : (
          <>
            {task.status === 'pending' && (
              <Pressable
                onPress={startTask}
                disabled={saving}
                className="flex-1 bg-bg-elevated border border-[#2a2a2a] rounded-2xl py-4 items-center"
              >
                <Text className="text-neutral-300 font-medium">Start</Text>
              </Pressable>
            )}
            <Pressable
              onPress={completeTask}
              disabled={saving}
              className="flex-1 bg-accent rounded-2xl py-4 items-center"
            >
              {saving
                ? <ActivityIndicator color="#000" />
                : <Text className="text-black font-semibold">Mark done</Text>
              }
            </Pressable>
          </>
        )}
      </View>
    </BottomSheet>
  )
}
