import { useEffect, useRef, useState, type FormEvent } from 'react'
import { createConversation, sendMessage, submitFeedback } from './api'
import type { FeedbackRating, Message, User } from './types'

interface Props {
  token: string
  user: User
  onSignOut: () => void
}

export function Chat({ token, user, onSignOut }: Props) {
  const [conversationId, setConversationId] = useState<number | null>(null)
  const [messages, setMessages] = useState<Message[]>([])
  const [streamingText, setStreamingText] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    createConversation(token)
      .then((conversation) => setConversationId(conversation.id))
      .catch(() => setError('No se pudo iniciar la conversación.'))
  }, [token])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, streamingText])

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    if (!draft.trim() || !conversationId || sending) return

    const content = draft.trim()
    setDraft('')
    setError(null)
    setSending(true)
    setStreamingText('')

    try {
      const assistant = await sendMessage(token, conversationId, content, {
        onUserMessage: (m) => setMessages((prev) => [...prev, m]),
        onToken: (chunk) => setStreamingText((prev) => (prev ?? '') + chunk),
      })
      setMessages((prev) => [...prev, assistant])
    } catch {
      setError('No se pudo enviar el mensaje. Intenta de nuevo.')
    } finally {
      setStreamingText(null)
      setSending(false)
    }
  }

  async function handleFeedback(messageId: number, rating: FeedbackRating) {
    try {
      const { feedback } = await submitFeedback(token, messageId, rating)
      setMessages((prev) =>
        prev.map((m) => (m.id === messageId ? { ...m, feedback } : m)),
      )
    } catch {
      // best-effort — a failed feedback click isn't worth a visible error
    }
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

      <div className="flex-1 overflow-y-auto py-4">
        {messages.length === 0 && streamingText === null && (
          <p className="text-muted">
            Cuéntame qué estás buscando — nivel de estudios, área, país de
            destino — y te ayudo a encontrar becas.
          </p>
        )}
        <ul className="flex flex-col gap-3">
          {messages.map((m) => (
            <li
              key={m.id}
              className={`max-w-[85%] rounded-2xl px-4 py-2 text-sm ${
                m.role === 'user'
                  ? 'ml-auto bg-owl-500 text-white'
                  : 'mr-auto bg-owl-50 text-ink'
              }`}
            >
              <p className="whitespace-pre-wrap">{m.content}</p>
              {m.citations.length > 0 && (
                <ul className="mt-2 flex flex-col gap-1 border-t border-current/20 pt-2 text-xs opacity-80">
                  {m.citations.map((c) => (
                    <li key={c.scholarship_id}>
                      <a
                        href={c.source_url}
                        target="_blank"
                        rel="noreferrer"
                        className="underline"
                      >
                        {c.title}
                      </a>
                    </li>
                  ))}
                </ul>
              )}
              {m.role === 'assistant' && (
                <div className="mt-2 flex gap-3 border-t border-current/20 pt-2">
                  <button
                    type="button"
                    onClick={() => handleFeedback(m.id, 'up')}
                    aria-label="Respuesta útil"
                    aria-pressed={m.feedback?.rating === 'up'}
                    className={`text-sm ${m.feedback?.rating === 'up' ? 'opacity-100' : 'opacity-40 hover:opacity-70'}`}
                  >
                    👍
                  </button>
                  <button
                    type="button"
                    onClick={() => handleFeedback(m.id, 'down')}
                    aria-label="Respuesta no útil"
                    aria-pressed={m.feedback?.rating === 'down'}
                    className={`text-sm ${m.feedback?.rating === 'down' ? 'opacity-100' : 'opacity-40 hover:opacity-70'}`}
                  >
                    👎
                  </button>
                </div>
              )}
            </li>
          ))}
          {streamingText !== null && (
            <li className="mr-auto max-w-[85%] rounded-2xl bg-owl-50 px-4 py-2 text-sm text-ink">
              <p className="whitespace-pre-wrap">
                {streamingText}
                {sending && <span className="animate-pulse">▍</span>}
              </p>
            </li>
          )}
        </ul>
        <div ref={bottomRef} />
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <form
        onSubmit={handleSubmit}
        className="flex gap-2 border-t border-owl-100 pt-4"
      >
        <input
          type="text"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Escribe tu pregunta…"
          disabled={!conversationId || sending}
          className="flex-1 rounded-full border border-owl-100 px-4 py-2 text-sm outline-none focus:border-owl-500"
        />
        <button
          type="submit"
          disabled={!conversationId || sending || !draft.trim()}
          className="rounded-full bg-owl-500 px-5 py-2 text-sm font-medium text-white transition hover:bg-owl-600 disabled:opacity-50"
        >
          Enviar
        </button>
      </form>
    </div>
  )
}
