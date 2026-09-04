export interface User {
  id: number
  email: string
  role: string
}

export interface Citation {
  scholarship_id: string
  title: string
  source_url: string
}

export interface Message {
  id: number
  role: 'user' | 'assistant'
  content: string
  agent: string | null
  citations: Citation[]
  created_at: string
}

export interface Conversation {
  id: number
  title: string | null
  created_at: string
  messages?: Message[]
}
