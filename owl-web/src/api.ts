import type {
  Conversation,
  Feedback,
  FeedbackRating,
  Features,
  Message,
  RoutingInfo,
  Scholarship,
  User,
} from './types'

const ADMIN_URL = import.meta.env.VITE_ADMIN_API_URL ?? 'http://localhost:3000'

export class ApiError extends Error {
  status: number

  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const res = await fetch(`${ADMIN_URL}${path}`, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...options.headers },
  })

  if (!res.ok) {
    const body = await res.json().catch(() => ({}) as Record<string, unknown>)
    const message =
      (body.error as string) ||
      (Array.isArray(body.errors) ? body.errors.join(', ') : null) ||
      `HTTP ${res.status}`
    throw new ApiError(message, res.status)
  }

  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}

function authHeader(token: string) {
  return { Authorization: `Bearer ${token}` }
}

export function register(email: string, password: string) {
  return request<{ token: string; user: User }>('/api/registrations', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  })
}

export function login(email: string, password: string) {
  return request<{ token: string; user: User }>('/api/session', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  })
}

export function createConversation(token: string) {
  return request<Conversation>('/api/conversations', {
    method: 'POST',
    headers: authHeader(token),
  })
}

/**
 * Which UI to show — the chat agent, or (AI_SCHOLARSHIP_AGENT off) a plain
 * scholarship list + search bar. Public, no token: owl-admin's Flipper flag,
 * not per-user state.
 */
export async function getFeatures(): Promise<Features> {
  const data = await request<Partial<Features>>('/api/features')
  // Fail open to the current behavior if the field is ever missing.
  return { ai_scholarship_agent: data.ai_scholarship_agent ?? true }
}

export function listScholarships(token: string, query: string) {
  const params = query.trim()
    ? `?q=${encodeURIComponent(query.trim())}`
    : ''
  return request<Scholarship[]>(`/api/scholarships${params}`, {
    headers: authHeader(token),
  })
}

export function submitFeedback(
  token: string,
  messageId: number,
  rating: FeedbackRating,
  reason?: string,
) {
  return request<{ feedback: Feedback }>(
    `/api/messages/${messageId}/feedback`,
    {
      method: 'POST',
      headers: authHeader(token),
      body: JSON.stringify({ rating, reason }),
    },
  )
}

interface SendHandlers {
  onUserMessage: (message: Message) => void
  onToken: (chunk: string) => void
  onRouting?: (info: RoutingInfo) => void
}

/**
 * Posts a message to owl-admin and consumes the SSE stream it relays back
 * from owl-api: `routing` (which agent took the turn), `user_message` (the
 * persisted user turn), then `token` per chunk of the answer, then `done`
 * (the persisted assistant message) or `error`. Resolves with the persisted
 * assistant `Message`.
 *
 * SSE-shaped over `fetch` rather than `EventSource`, which is GET-only with
 * no request body or custom headers — this needs both.
 */
export async function sendMessage(
  token: string,
  conversationId: number,
  content: string,
  handlers: SendHandlers,
): Promise<Message> {
  const res = await fetch(
    `${ADMIN_URL}/api/conversations/${conversationId}/messages`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...authHeader(token) },
      body: JSON.stringify({ content }),
    },
  )

  if (!res.ok || !res.body) {
    const body = await res.json().catch(() => ({}) as Record<string, unknown>)
    throw new ApiError(
      (body.error as string) ?? `HTTP ${res.status}`,
      res.status,
    )
  }

  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  let assistant: Message | null = null
  let streamError: string | null = null

  while (true) {
    const { value, done } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })

    let separatorIndex: number
    while ((separatorIndex = buffer.indexOf('\n\n')) !== -1) {
      const rawEvent = buffer.slice(0, separatorIndex)
      buffer = buffer.slice(separatorIndex + 2)

      let eventName = 'message'
      let data: Record<string, unknown> = {}
      for (const line of rawEvent.split('\n')) {
        if (line.startsWith('event: ')) eventName = line.slice('event: '.length)
        else if (line.startsWith('data: '))
          data = JSON.parse(line.slice('data: '.length))
      }

      if (eventName === 'routing') {
        handlers.onRouting?.(data as unknown as RoutingInfo)
      } else if (eventName === 'user_message') {
        handlers.onUserMessage(data as unknown as Message)
      } else if (eventName === 'token' && typeof data.content === 'string') {
        handlers.onToken(data.content)
      } else if (eventName === 'error') {
        streamError = (data.detail as string) ?? 'stream error'
      } else if (eventName === 'done') {
        assistant = data as unknown as Message
      }
    }
  }

  if (streamError) throw new ApiError(streamError, 502)
  if (!assistant) throw new ApiError('stream ended without a done event', 502)
  return assistant
}
