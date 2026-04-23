import { useState } from 'react'
import {
  View, Text, TextInput, Pressable, KeyboardAvoidingView,
  Platform, ActivityIndicator, ScrollView,
} from 'react-native'
import { useAuth } from '@/hooks/useAuth'

export default function Login() {
  const { signIn } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function onSubmit() {
    if (!email.trim() || !password) return
    setLoading(true)
    setError(null)
    const { error } = await signIn(email.trim(), password)
    setLoading(false)
    if (error) setError(error)
  }

  return (
    <KeyboardAvoidingView
      className="flex-1 bg-bg"
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <ScrollView
        contentContainerStyle={{ flexGrow: 1 }}
        keyboardShouldPersistTaps="handled"
      >
        <View className="flex-1 items-center justify-center px-6">
          {/* Logo */}
          <View className="w-20 h-20 rounded-3xl bg-bg-card border border-[#2a2a2a] items-center justify-center mb-6">
            <Text className="text-accent text-4xl font-bold">B</Text>
          </View>
          <Text className="text-white text-2xl font-bold tracking-tight mb-1">The Backdoor</Text>
          <Text className="text-neutral-500 text-sm mb-10">Staff task board</Text>

          {/* Form */}
          <View className="w-full gap-3">
            <TextInput
              className="bg-bg-card border border-[#2a2a2a] rounded-2xl px-4 py-4 text-white text-base"
              placeholder="Email"
              placeholderTextColor="#6b7280"
              value={email}
              onChangeText={setEmail}
              keyboardType="email-address"
              autoCapitalize="none"
              autoComplete="email"
            />
            <TextInput
              className="bg-bg-card border border-[#2a2a2a] rounded-2xl px-4 py-4 text-white text-base"
              placeholder="Password"
              placeholderTextColor="#6b7280"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              autoComplete="current-password"
            />

            {error && (
              <View className="bg-red-500/10 border border-red-500/30 rounded-xl px-4 py-3">
                <Text className="text-red-400 text-sm">{error}</Text>
              </View>
            )}

            <Pressable
              onPress={onSubmit}
              disabled={loading}
              className="bg-accent rounded-2xl py-4 items-center mt-1 active:opacity-80"
            >
              {loading
                ? <ActivityIndicator color="#000" />
                : <Text className="text-black font-semibold text-base">Sign in</Text>
              }
            </Pressable>
          </View>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  )
}
