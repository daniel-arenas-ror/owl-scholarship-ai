import { useEffect, useState } from 'react'
import { getFeatures } from './api'
import { AuthForm } from './AuthForm'
import { Chat } from './Chat'
import { ScholarshipBrowser } from './ScholarshipBrowser'
import type { Features } from './types'
import { useAuth } from './useAuth'

function App() {
  const { auth, signIn, signOut } = useAuth()
  // Defaults to the chat agent (current behavior) until owl-admin answers, or
  // if it's ever unreachable — the flag is a UI switch, not a security gate.
  const [features, setFeatures] = useState<Features>({
    ai_scholarship_agent: true,
  })

  useEffect(() => {
    getFeatures()
      .then(setFeatures)
      .catch(() => {
        // network hiccup — keep the default
      })
  }, [])

  return (
    <main className="min-h-dvh bg-paper text-ink dark:bg-owl-700 dark:text-white">
      {auth ? (
        features.ai_scholarship_agent ? (
          <Chat token={auth.token} user={auth.user} onSignOut={signOut} />
        ) : (
          <ScholarshipBrowser
            token={auth.token}
            user={auth.user}
            onSignOut={signOut}
          />
        )
      ) : (
        <AuthForm onAuthenticated={signIn} />
      )}
    </main>
  )
}

export default App
