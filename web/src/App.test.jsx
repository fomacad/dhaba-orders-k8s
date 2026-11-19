import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import App from './App.jsx'

const sampleMenu = {
  items: [
    { id: 1, name: 'Chicken Karahi', price: 12 },
    { id: 2, name: 'Daal Chawal', price: 7 },
  ],
}
const sampleOrders = { orders: [{ id: 1, dish: 'Chicken Karahi', status: 'cooking' }] }
const sampleStats = { orders_per_minute: 4, top_dishes: ['Chicken Karahi', 'Daal Chawal'] }

function mockFetchFor(url) {
  if (url === '/api/menu') return { ok: true, json: async () => sampleMenu }
  if (url === '/api/orders') return { ok: true, json: async () => sampleOrders }
  if (url === '/api/stats') return { ok: true, json: async () => sampleStats }
  return { ok: false, json: async () => ({}) }
}

beforeEach(() => {
  global.fetch = vi.fn((url, opts) => Promise.resolve(mockFetchFor(url, opts)))
})

afterEach(() => {
  vi.restoreAllMocks()
})

describe('App', () => {
  it('renders menu items fetched from /api/menu', async () => {
    render(<App />)
    expect(await screen.findByText(/Chicken Karahi - \$12/)).toBeInTheDocument()
    expect(screen.getByText(/Daal Chawal - \$7/)).toBeInTheDocument()
  })

  it('renders kitchen orders fetched from /api/orders', async () => {
    render(<App />)
    expect(await screen.findByText(/#1 Chicken Karahi - cooking/)).toBeInTheDocument()
  })

  it('renders live stats fetched from /api/stats', async () => {
    render(<App />)
    expect(await screen.findByText(/Orders\/min: 4/)).toBeInTheDocument()
    expect(screen.getByText(/Chicken Karahi, Daal Chawal/)).toBeInTheDocument()
  })

  it('POSTs to /api/orders when a menu item\'s Order button is clicked', async () => {
    render(<App />)
    const buttons = await screen.findAllByText('Order', { selector: 'button' })
    fireEvent.click(buttons[0])

    await waitFor(() => {
      const postCall = global.fetch.mock.calls.find(([, opts]) => opts?.method === 'POST')
      expect(postCall).toBeTruthy()
      expect(postCall[0]).toBe('/api/orders')
      expect(JSON.parse(postCall[1].body)).toEqual({ dish: 'Chicken Karahi' })
    })
  })
})
