import { Route, Routes } from 'react-router-dom'
import Login from './pages/Login'
import Today from './pages/Today'
import MyTasks from './pages/MyTasks'
import Admin from './pages/Admin'
import AppShell from './components/layout/AppShell'
import { ProtectedRoute } from './components/auth/ProtectedRoute'

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        element={
          <ProtectedRoute>
            <AppShell />
          </ProtectedRoute>
        }
      >
        <Route path="/" element={<Today />} />
        <Route path="/mine" element={<MyTasks />} />
        <Route
          path="/admin"
          element={
            <ProtectedRoute adminOnly>
              <Admin />
            </ProtectedRoute>
          }
        />
      </Route>
    </Routes>
  )
}
