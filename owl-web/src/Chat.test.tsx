import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, expect, test, vi } from 'vitest'
import { Chat } from './Chat'
import type { User } from './types'

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status })
}

function sseResponse(events: { event: string; data: unknown }[]) {
  const encoder = new TextEncoder()
  const text = events
    .map((e) => `event: ${e.event}\ndata: ${JSON.stringify(e.data)}\n\n`)
    .join('')
  return new Response(
    new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode(text))
        controller.close()
      },
    }),
    { status: 200 },
  )
}

const testUser: User = { id: 1, email: 'a@b.com', role: 'student' }

const generalStream = [
  {
    event: 'routing',
    data: { route: 'general', scholarship_id: null, scholarship_title: null },
  },
  {
    event: 'user_message',
    data: {
      id: 1,
      role: 'user',
      content: 'hola',
      agent: null,
      citations: [],
      created_at: '2026-01-01',
    },
  },
  { event: 'token', data: { content: 'Hola' } },
  { event: 'token', data: { content: ' mundo' } },
  {
    event: 'done',
    data: {
      id: 2,
      role: 'assistant',
      content: 'Hola mundo',
      agent: 'general_advisor',
      citations: [],
      feedback: null,
      created_at: '2026-01-01',
    },
  },
]

const expertStream = [
  {
    event: 'routing',
    data: {
      route: 'expert',
      scholarship_id: '7',
      scholarship_title: 'Beca Chevening',
    },
  },
  {
    event: 'user_message',
    data: {
      id: 1,
      role: 'user',
      content: 'requisitos de Chevening',
      agent: null,
      citations: [],
      created_at: '2026-01-01',
    },
  },
  { event: 'token', data: { content: 'Chevening exige…' } },
  {
    event: 'done',
    data: {
      id: 2,
      role: 'assistant',
      content: 'Chevening exige…',
      agent: 'scholarship_expert',
      citations: [
        {
          scholarship_id: '7',
          title: 'Beca Chevening',
          source_url: 'https://chevening.org',
        },
      ],
      feedback: null,
      created_at: '2026-01-01',
    },
  },
]

function stubFetch(stream: { event: string; data: unknown }[] = generalStream) {
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string) => {
      if (url.includes('/api/conversations/1/messages')) {
        return Promise.resolve(sseResponse(stream))
      }
      if (url.includes('/feedback')) {
        return Promise.resolve(
          jsonResponse({ feedback: { rating: 'up', reason: null } }),
        )
      }
      if (url.includes('/api/conversations')) {
        return Promise.resolve(
          jsonResponse({ id: 1, title: null, created_at: '2026-01-01' }, 201),
        )
      }
      return Promise.resolve(jsonResponse({}))
    }),
  )
}

beforeEach(() => {
  stubFetch()
})

test('sends a message and renders the streamed answer', async () => {
  const user = userEvent.setup()
  render(<Chat token="t1" user={testUser} onSignOut={() => {}} />)

  const input = await screen.findByPlaceholderText('Escribe tu pregunta…')
  await waitFor(() => expect(input).not.toBeDisabled())

  await user.type(input, 'hola')
  await user.click(screen.getByRole('button', { name: 'Enviar' }))

  await waitFor(() =>
    expect(screen.getByText('Hola mundo')).toBeInTheDocument(),
  )
  expect(screen.getByText('hola')).toBeInTheDocument()
})

test('shows the expert hand-off label when the expert agent answered', async () => {
  stubFetch(expertStream)
  const user = userEvent.setup()
  render(<Chat token="t1" user={testUser} onSignOut={() => {}} />)

  const input = await screen.findByPlaceholderText('Escribe tu pregunta…')
  await waitFor(() => expect(input).not.toBeDisabled())
  await user.type(input, 'requisitos de Chevening')
  await user.click(screen.getByRole('button', { name: 'Enviar' }))

  await waitFor(() =>
    expect(screen.getByText('Chevening exige…')).toBeInTheDocument(),
  )
  expect(screen.getByText(/Experto en Beca Chevening/)).toBeInTheDocument()
})

test('records feedback on an assistant message', async () => {
  const user = userEvent.setup()
  render(<Chat token="t1" user={testUser} onSignOut={() => {}} />)

  const input = await screen.findByPlaceholderText('Escribe tu pregunta…')
  await waitFor(() => expect(input).not.toBeDisabled())
  await user.type(input, 'hola')
  await user.click(screen.getByRole('button', { name: 'Enviar' }))

  const thumbsUp = await screen.findByRole('button', { name: 'Respuesta útil' })
  await user.click(thumbsUp)

  await waitFor(() => expect(thumbsUp).toHaveAttribute('aria-pressed', 'true'))
})
