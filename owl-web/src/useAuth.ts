import { useCallback, useState } from 'react'
import type { User } from './types'

const STORAGE_KEY = 'owl.auth'

interface StoredAuth {
  token: string
  user: User
}

function loadStored(): StoredAuth | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? (JSON.parse(raw) as StoredAuth) : null
  } catch {
    return null
  }
}

export function useAuth() {
  const [auth, setAuth] = useState<StoredAuth | null>(() => loadStored())

  const signIn = useCallback((token: string, user: User) => {
    const value = { token, user }
    setAuth(value)
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(value))
    } catch {
      // private browsing / storage disabled — the session still works in memory
    }
  }, [])

  const signOut = useCallback(() => {
    setAuth(null)
    try {
      localStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }, [])

  return { auth, signIn, signOut }
}
