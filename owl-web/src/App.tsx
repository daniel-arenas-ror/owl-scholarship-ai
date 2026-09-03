import { useEffect, useState } from 'react'

const ADMIN_URL = import.meta.env.VITE_ADMIN_API_URL ?? 'http://localhost:3000'
const API_URL = import.meta.env.VITE_OWL_API_URL ?? 'http://localhost:8000'

type Probe = { name: string; url: string; status: 'checking' | 'up' | 'down' }

const TARGETS: Omit<Probe, 'status'>[] = [
  { name: 'owl-api', url: `${API_URL}/health` },
  { name: 'owl-admin', url: `${ADMIN_URL}/up` },
]

function App() {
  const [probes, setProbes] = useState<Probe[]>(
    TARGETS.map((t) => ({ ...t, status: 'checking' })),
  )

  useEffect(() => {
    let cancelled = false
    Promise.all(
      TARGETS.map(async (t) => {
        try {
          const res = await fetch(t.url, { mode: 'cors' })
          return { ...t, status: res.ok ? 'up' : 'down' } as Probe
        } catch {
          return { ...t, status: 'down' } as Probe
        }
      }),
    ).then((next) => {
      if (!cancelled) setProbes(next)
    })
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <main className="min-h-dvh bg-paper text-ink dark:bg-owl-700 dark:text-white">
      <div className="mx-auto flex max-w-xl flex-col gap-8 px-6 py-20">
        <header className="flex items-center gap-3">
          <span aria-hidden className="text-3xl">
            🦉
          </span>
          <h1 className="font-display text-3xl font-semibold tracking-tight">
            Owl
          </h1>
        </header>

        <p className="text-muted dark:text-owl-100">
          Asistente de búsqueda de becas para estudiantes en Colombia. Este es
          el esqueleto de la Fase&nbsp;0 — la interfaz de chat llega en la
          Fase&nbsp;1.
        </p>

        <section className="flex flex-col gap-3">
          <h2 className="text-xs font-medium uppercase tracking-widest text-muted">
            Estado de los servicios
          </h2>
          <ul className="flex flex-col gap-2">
            {probes.map((p) => (
              <li
                key={p.name}
                className="flex items-center justify-between rounded-lg border border-owl-100 bg-white px-4 py-3 dark:border-owl-600 dark:bg-owl-600/40"
              >
                <span className="font-mono text-sm">{p.name}</span>
                <StatusPill status={p.status} />
              </li>
            ))}
          </ul>
        </section>
      </div>
    </main>
  )
}

function StatusPill({ status }: { status: Probe['status'] }) {
  const label =
    status === 'up' ? 'en línea' : status === 'down' ? 'sin conexión' : '…'
  const tone =
    status === 'up'
      ? 'bg-emerald-100 text-emerald-800'
      : status === 'down'
        ? 'bg-red-100 text-red-800'
        : 'bg-owl-50 text-owl-600'
  return (
    <span
      className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${tone}`}
      role="status"
    >
      {label}
    </span>
  )
}

export default App
