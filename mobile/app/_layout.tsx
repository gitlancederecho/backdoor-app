import '../global.css'
import { useEffect } from 'react'
import { Stack, useRouter, useSegments } from 'expo-router'
import { StatusBar } from 'expo-status-bar'
import { AuthProvider, useAuth } from '@/hooks/useAuth'

function RouteGuard() {
  const { session, loading } = useAuth()
  const segments = useSegments()
  const router = useRouter()

  useEffect(() => {
    if (loading) return
    const inTabs = segments[0] === '(tabs)'
    if (!session && inTabs) router.replace('/login')
    if (session && !inTabs) router.replace('/(tabs)/')
  }, [session, loading, segments, router])

  return null
}

export default function RootLayout() {
  return (
    <AuthProvider>
      <RouteGuard />
      <StatusBar style="light" backgroundColor="#0a0a0a" />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#0a0a0a' } }}>
        <Stack.Screen name="login" />
        <Stack.Screen name="(tabs)" />
      </Stack>
    </AuthProvider>
  )
}
