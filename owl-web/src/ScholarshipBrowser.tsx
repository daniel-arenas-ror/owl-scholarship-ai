import { useEffect, useState, type FormEvent } from 'react'
import { listScholarships } from './api'
import type { Scholarship, User } from './types'

interface Props {
  token: string
  user: User
  onSignOut: () => void
}

/**
 * The AI_SCHOLARSHIP_AGENT-off screen: no chat, no OpenAI call — just the
 * shared scholarships table, listed and searchable.
 */
export function ScholarshipBrowser({ token, user, onSignOut }: Props) {
  const [query, setQuery] = useState('')
  const [scholarships, setScholarships] = useState<Scholarship[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  function search(q: string) {
    setLoading(true)
    setError(null)
    listScholarships(token, q)
      .then(setScholarships)
      .catch(() => setError('No se pudieron cargar las becas.'))
      .finally(() => setLoading(false))
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- load the full list once on mount
  useEffect(() => search(''), [token])

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    search(query)
  }

  return (
    <div className="mx-auto flex h-dvh max-w-2xl flex-col px-6 py-6">
      <header className="flex items-center justify-between border-b border-owl-100 pb-4">
        <div className="flex items-center gap-3">
          <span aria-hidden className="text-2xl">
            🦉
          </span>
          <h1 className="font-display text-xl font-semibold tracking-tight">
            Owl
          </h1>
        </div>
        <div className="flex items-center gap-3 text-sm text-muted">
          <span>{user.email}</span>
          <button
            type="button"
            onClick={onSignOut}
            className="underline underline-offset-2"
          >
            Salir
          </button>
        </div>
      </header>

      <form
        onSubmit={handleSubmit}
        className="flex gap-2 border-b border-owl-100 py-4"
      >
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Buscar por país, área, nivel…"
          aria-label="Buscar becas"
          className="flex-1 rounded-full border border-owl-100 px-4 py-2 text-sm outline-none focus:border-owl-500"
        />
        <button
          type="submit"
          disabled={loading}
          className="rounded-full bg-owl-500 px-5 py-2 text-sm font-medium text-white transition hover:bg-owl-600 disabled:opacity-50"
        >
          Buscar
        </button>
      </form>

      <div className="flex-1 overflow-y-auto py-4">
        {error && <p className="text-sm text-red-600">{error}</p>}
        {!error && loading && <p className="text-muted">Cargando becas…</p>}
        {!error && !loading && scholarships.length === 0 && (
          <p className="text-muted">No encontramos becas con esa búsqueda.</p>
        )}
        <ul className="flex flex-col gap-3">
          {scholarships.map((s) => (
            <li
              key={s.id}
              className="rounded-2xl bg-owl-50 px-4 py-3 text-sm text-ink"
            >
              <p className="font-medium">{s.title}</p>
              <p className="text-xs text-muted">
                {s.provider} · {s.country}
              </p>
              {(s.levels.length > 0 || s.fields.length > 0) && (
                <p className="mt-1 text-xs opacity-80">
                  {[...s.levels, ...s.fields].join(' · ')}
                </p>
              )}
              {s.deadline && (
                <p className="mt-1 text-xs opacity-80">
                  Fecha límite: {s.deadline}
                </p>
              )}
              <a
                href={s.source_url}
                target="_blank"
                rel="noreferrer"
                className="mt-2 inline-block text-xs underline"
              >
                Ver convocatoria ↗
              </a>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
