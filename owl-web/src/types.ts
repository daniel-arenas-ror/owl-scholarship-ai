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

export type FeedbackRating = 'up' | 'down'

export interface Feedback {
  rating: FeedbackRating
  reason: string | null
}

export interface Message {
  id: number
  role: 'user' | 'assistant'
  content: string
  agent: string | null
  citations: Citation[]
  feedback?: Feedback | null
  created_at: string
}

export interface Conversation {
  id: number
  title: string | null
  created_at: string
  messages?: Message[]
}

export type AgentRoute = 'general' | 'expert'

export interface RoutingInfo {
  route: AgentRoute
  scholarship_id: string | null
  scholarship_title: string | null
}

export interface Features {
  ai_scholarship_agent: boolean
}

export interface Scholarship {
  id: number
  title: string
  provider: string
  country: string
  fields: string[]
  levels: string[]
  funding_type: string | null
  amount_note: string | null
  deadline: string | null
  eligibility_text: string | null
  source_url: string
}
