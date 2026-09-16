import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { ScholarshipBrowser } from './ScholarshipBrowser'
import type { Scholarship, User } from './types'

function jsonResponse(body: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(body), { status }))
}

const testUser: User = { id: 1, email: 'a@b.com', role: 'student' }

const daad: Scholarship = {
  id: 4,
  title: 'Becas DAAD para maestría y doctorado en Alemania',
  provider: 'DAAD',
  country: 'CO',
  fields: [],
  levels: ['maestría', 'doctorado'],
  funding_type: null,
  amount_note: null,
  deadline: 'Varía por convocatoria',
  eligibility_text: null,
  source_url: 'https://www.daad.de',
}

const chevening: Scholarship = {
  id: 3,
  title: 'Chevening Scholarships',
  provider: 'Gobierno del Reino Unido',
  country: 'CO',
  fields: [],
  levels: ['maestría'],
  funding_type: null,
  amount_note: null,
  deadline: null,
  eligibility_text: null,
  source_url: 'https://www.chevening.org',
}

function stubFetch(all: Scholarship[], filtered: Scholarship[]) {
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string) => {
      if (url.includes('/api/scholarships?q=')) return jsonResponse(filtered)
      if (url.includes('/api/scholarships')) return jsonResponse(all)
      return jsonResponse({})
    }),
  )
}

test('lists every scholarship on mount', async () => {
  stubFetch([daad, chevening], [chevening])
  render(
    <ScholarshipBrowser token="t1" user={testUser} onSignOut={() => {}} />,
  )

  await waitFor(() => {
    expect(screen.getByText(/Becas DAAD/)).toBeInTheDocument()
  })
  expect(screen.getByText('Chevening Scholarships')).toBeInTheDocument()
  expect(screen.getByText(/maestría · doctorado/)).toBeInTheDocument()
})

test('searches and narrows the list', async () => {
  stubFetch([daad, chevening], [chevening])
  const user = userEvent.setup()
  render(
    <ScholarshipBrowser token="t1" user={testUser} onSignOut={() => {}} />,
  )

  await waitFor(() => {
    expect(screen.getByText(/Becas DAAD/)).toBeInTheDocument()
  })

  await user.type(screen.getByLabelText('Buscar becas'), 'chevening')
  await user.click(screen.getByRole('button', { name: 'Buscar' }))

  await waitFor(() => {
    expect(screen.queryByText(/Becas DAAD/)).not.toBeInTheDocument()
  })
  expect(screen.getByText('Chevening Scholarships')).toBeInTheDocument()
})

test('shows an empty state when nothing matches', async () => {
  stubFetch([daad], [])
  const user = userEvent.setup()
  render(
    <ScholarshipBrowser token="t1" user={testUser} onSignOut={() => {}} />,
  )

  await waitFor(() => {
    expect(screen.getByText(/Becas DAAD/)).toBeInTheDocument()
  })

  await user.type(screen.getByLabelText('Buscar becas'), 'nada existe')
  await user.click(screen.getByRole('button', { name: 'Buscar' }))

  await waitFor(() => {
    expect(
      screen.getByText('No encontramos becas con esa búsqueda.'),
    ).toBeInTheDocument()
  })
})
