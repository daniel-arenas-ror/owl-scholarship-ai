import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, expect, test, vi } from 'vitest'
import App from './App'

beforeEach(() => {
  window.localStorage.clear()
})

function jsonResponse(body: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(body), { status }))
}

test('shows the login form first', () => {
  render(<App />)
  expect(screen.getByRole('heading', { name: 'Owl' })).toBeInTheDocument()
  expect(screen.getByLabelText('Correo')).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Ingresar' })).toBeInTheDocument()
})

test('logs in and starts a conversation', async () => {
  const user = userEvent.setup()

  vi.stubGlobal(
    'fetch',
    vi.fn((url: string) => {
      if (url.includes('/api/session')) {
        return jsonResponse(
          { token: 't1', user: { id: 1, email: 'a@b.com', role: 'student' } },
          201,
        )
      }
      if (url.includes('/api/conversations')) {
        return jsonResponse(
          { id: 1, title: null, created_at: '2026-01-01' },
          201,
        )
      }
      return jsonResponse({})
    }),
  )

  render(<App />)

  await user.type(screen.getByLabelText('Correo'), 'a@b.com')
  await user.type(screen.getByLabelText('Contraseña'), 'password123')
  await user.click(screen.getByRole('button', { name: 'Ingresar' }))

  await waitFor(() => {
    expect(
      screen.getByPlaceholderText('Escribe tu pregunta…'),
    ).toBeInTheDocument()
  })
  expect(screen.getByText('a@b.com')).toBeInTheDocument()
})
