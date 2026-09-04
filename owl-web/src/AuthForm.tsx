import { useState, type FormEvent } from 'react'
import { login, register } from './api'
import type { User } from './types'

type Mode = 'login' | 'register'

interface Props {
  onAuthenticated: (token: string, user: User) => void
}

export function AuthForm({ onAuthenticated }: Props) {
  const [mode, setMode] = useState<Mode>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)
    try {
      const action = mode === 'login' ? login : register
      const { token, user } = await action(email, password)
      onAuthenticated(token, user)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Algo salió mal')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="mx-auto flex max-w-sm flex-col gap-6 px-6 py-24">
      <header className="flex items-center gap-3">
        <span aria-hidden className="text-3xl">
          🦉
        </span>
        <h1 className="font-display text-3xl font-semibold tracking-tight">
          Owl
        </h1>
      </header>

      <p className="text-muted">
        {mode === 'login'
          ? 'Ingresa a tu cuenta.'
          : 'Crea una cuenta para empezar a buscar becas.'}
      </p>

      <form onSubmit={handleSubmit} className="flex flex-col gap-3">
        <label className="flex flex-col gap-1 text-sm">
          Correo
          <input
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="rounded-lg border border-owl-100 px-3 py-2 outline-none focus:border-owl-500"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Contraseña
          <input
            type="password"
            required
            minLength={8}
            autoComplete={
              mode === 'login' ? 'current-password' : 'new-password'
            }
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="rounded-lg border border-owl-100 px-3 py-2 outline-none focus:border-owl-500"
          />
        </label>

        {error && <p className="text-sm text-red-600">{error}</p>}

        <button
          type="submit"
          disabled={busy}
          className="mt-2 rounded-lg bg-owl-500 px-4 py-2 font-medium text-white transition hover:bg-owl-600 disabled:opacity-50"
        >
          {busy
            ? 'Un momento…'
            : mode === 'login'
              ? 'Ingresar'
              : 'Crear cuenta'}
        </button>
      </form>

      <button
        type="button"
        onClick={() => setMode(mode === 'login' ? 'register' : 'login')}
        className="text-sm text-owl-500 underline underline-offset-2"
      >
        {mode === 'login'
          ? '¿No tienes cuenta? Regístrate'
          : '¿Ya tienes cuenta? Ingresa'}
      </button>
    </div>
  )
}
