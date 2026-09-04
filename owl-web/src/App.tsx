import { AuthForm } from './AuthForm'
import { Chat } from './Chat'
import { useAuth } from './useAuth'

function App() {
  const { auth, signIn, signOut } = useAuth()

  return (
    <main className="min-h-dvh bg-paper text-ink dark:bg-owl-700 dark:text-white">
      {auth ? (
        <Chat token={auth.token} user={auth.user} onSignOut={signOut} />
      ) : (
        <AuthForm onAuthenticated={signIn} />
      )}
    </main>
  )
}

export default App
