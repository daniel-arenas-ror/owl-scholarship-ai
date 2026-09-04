import '@testing-library/jest-dom/vitest'

// Recent Node versions ship their own experimental localStorage, which can
// shadow jsdom's and lack methods like .clear(). Force a real in-memory
// implementation for tests regardless of the host Node version.
class MemoryStorage implements Storage {
  private store = new Map<string, string>()

  get length() {
    return this.store.size
  }

  clear() {
    this.store.clear()
  }

  getItem(key: string) {
    return this.store.has(key) ? (this.store.get(key) as string) : null
  }

  key(index: number) {
    return Array.from(this.store.keys())[index] ?? null
  }

  removeItem(key: string) {
    this.store.delete(key)
  }

  setItem(key: string, value: string) {
    this.store.set(key, String(value))
  }
}

Object.defineProperty(globalThis, 'localStorage', {
  value: new MemoryStorage(),
  writable: true,
  configurable: true,
})

// jsdom doesn't implement layout, so it has no scrollIntoView — Chat.tsx
// calls it on every new message.
Element.prototype.scrollIntoView = () => {}
