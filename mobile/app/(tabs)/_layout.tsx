import { Tabs } from 'expo-router'
import { useAuth } from '@/hooks/useAuth'
import { Text } from 'react-native'

export default function TabLayout() {
  const { isAdmin } = useAuth()

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: '#0a0a0a',
          borderTopColor: '#2a2a2a',
          borderTopWidth: 1,
          paddingTop: 6,
        },
        tabBarActiveTintColor: '#e8b84b',
        tabBarInactiveTintColor: '#6b7280',
        tabBarLabelStyle: { fontSize: 11, marginBottom: 4 },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Today',
          tabBarIcon: ({ color }) => <TabIcon color={color} icon="board" />,
        }}
      />
      <Tabs.Screen
        name="mine"
        options={{
          title: 'Mine',
          tabBarIcon: ({ color }) => <TabIcon color={color} icon="user" />,
        }}
      />
      <Tabs.Screen
        name="admin"
        options={{
          title: 'Admin',
          href: isAdmin ? '/(tabs)/admin' : null,
          tabBarIcon: ({ color }) => <TabIcon color={color} icon="settings" />,
        }}
      />
    </Tabs>
  )
}

function TabIcon({ color, icon }: { color: string; icon: 'board' | 'user' | 'settings' }) {
  const icons = { board: '▦', user: '◉', settings: '⚙' }
  return <Text style={{ color, fontSize: 18 }}>{icons[icon]}</Text>
}
