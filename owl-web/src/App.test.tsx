import { render, screen } from '@testing-library/react'
import { beforeEach, expect, test, vi } from 'vitest'
import App from './App'

beforeEach(() => {
  vi.stubGlobal(
    'fetch',
    vi.fn(() => Promise.resolve(new Response('', { status: 200 }))),
  )
})

test('renders the app title and both service probes', async () => {
  render(<App />)
  expect(screen.getByRole('heading', { name: 'Owl' })).toBeInTheDocument()
  expect(screen.getByText('owl-api')).toBeInTheDocument()
  expect(screen.getByText('owl-admin')).toBeInTheDocument()
  // wait out the async probe so state settles inside act()
  expect(await screen.findAllByText('en línea')).toHaveLength(2)
})
