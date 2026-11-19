import { useEffect, useState } from 'react'

function useFetch(url, intervalMs) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false
    const load = () => {
      fetch(url)
        .then((r) => r.json())
        .then((d) => { if (!cancelled) setData(d) })
        .catch((e) => { if (!cancelled) setError(e.message) })
    }
    load()
    const id = intervalMs ? setInterval(load, intervalMs) : null
    return () => { cancelled = true; if (id) clearInterval(id) }
  }, [url, intervalMs])

  return { data, error }
}

function Menu({ onOrder }) {
  const { data } = useFetch('/api/menu', 0)
  const items = data?.items ?? []
  return (
    <section className="panel menu">
      <h2>Menu</h2>
      <ul className="menu-grid">
        {items.map((item) => (
          <li key={item.id} className="dish-card">
            <span className="dish">{item.name} - ${item.price}</span>
            <button onClick={() => onOrder(item)}>Order</button>
          </li>
        ))}
      </ul>
    </section>
  )
}

function Kitchen() {
  const { data } = useFetch('/api/orders', 3000)
  const orders = data?.orders ?? []
  return (
    <section className="panel kitchen">
      <h2>Kitchen</h2>
      <ul className="order-list">
        {orders.length === 0 && <li className="empty">No orders yet</li>}
        {orders.map((o) => (
          <li key={o.id} className={`order status-${o.status}`}>#{o.id} {o.dish} - {o.status}</li>
        ))}
      </ul>
    </section>
  )
}

function Stats() {
  const { data } = useFetch('/api/stats', 5000)
  return (
    <section className="panel stats">
      <h2>Live Stats</h2>
      <p className="stat-number">Orders/min: {data?.orders_per_minute ?? '-'}</p>
      <p className="stat-dishes">Top dishes: {(data?.top_dishes ?? []).join(', ')}</p>
    </section>
  )
}

export default function App() {
  const placeOrder = (item) => {
    fetch('/api/orders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ dish: item.name }),
    })
  }

  return (
    <main className="app">
      <header className="hero">
        <h1>Dhaba Orders</h1>
        <p className="tagline">Fresh off the tawa, straight to your table.</p>
      </header>
      <Menu onOrder={placeOrder} />
      <div className="side-by-side">
        <Kitchen />
        <Stats />
      </div>
    </main>
  )
}
