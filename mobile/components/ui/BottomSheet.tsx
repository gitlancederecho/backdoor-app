import { ReactNode } from 'react'
import {
  Modal, View, Text, Pressable,
  KeyboardAvoidingView, Platform, ScrollView,
} from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'

export function BottomSheet({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
}) {
  const insets = useSafeAreaInsets()

  return (
    <Modal
      visible={open}
      transparent
      animationType="slide"
      statusBarTranslucent
      onRequestClose={onClose}
    >
      <Pressable className="flex-1 bg-black/70 justify-end" onPress={onClose}>
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        >
          <Pressable
            onPress={(e) => e.stopPropagation()}
            className="bg-bg-card rounded-t-3xl border-t border-[#2a2a2a]"
          >
            {/* Drag handle */}
            <View className="items-center pt-3 pb-1">
              <View className="w-10 h-1 rounded-full bg-[#3a3a3a]" />
            </View>

            <View className="flex-row items-center justify-between px-5 py-3">
              {title ? (
                <Text className="text-white text-lg font-semibold flex-1 mr-4" numberOfLines={2}>
                  {title}
                </Text>
              ) : <View />}
              <Pressable
                onPress={onClose}
                hitSlop={12}
                className="w-9 h-9 rounded-full bg-bg-elevated items-center justify-center"
              >
                <Text className="text-neutral-400 text-base">✕</Text>
              </Pressable>
            </View>

            <ScrollView
              style={{ maxHeight: 560 }}
              contentContainerStyle={{
                paddingHorizontal: 20,
                paddingBottom: insets.bottom + 24,
              }}
              keyboardShouldPersistTaps="handled"
              showsVerticalScrollIndicator={false}
            >
              {children}
            </ScrollView>
          </Pressable>
        </KeyboardAvoidingView>
      </Pressable>
    </Modal>
  )
}
