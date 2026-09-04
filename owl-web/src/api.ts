import type { Conversation, Message, User } from './types'

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

export function postMessage(
  token: string,
  conversationId: number,
  content: string,
) {
  return request<{ user_message: Message; assistant_message: Message }>(
    `/api/conversations/${conversationId}/messages`,
    {
      method: 'POST',
      headers: authHeader(token),
      body: JSON.stringify({ content }),
    },
  )
}
