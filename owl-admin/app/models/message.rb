class Message < ApplicationRecord
  belongs_to :conversation
  has_one :feedback, dependent: :destroy
  has_one :annotation, dependent: :destroy
  enum :role, { user: 0, assistant: 1 }

  validates :content, presence: true

  LANGSMITH_HOST = ENV.fetch("LANGSMITH_HOST", "https://smith.langchain.com").freeze

  # Link to the LangSmith trace for this turn. owl-api sets `trace_run_id` to the
  # run id it passed to the graph; the `/o/-/` segment resolves to the caller's
  # default workspace.
  def trace_url
    return nil if trace_run_id.blank?

    project = ENV.fetch("LANGSMITH_PROJECT", "owl-dev")
    "#{LANGSMITH_HOST}/o/-/projects/p/#{project}/r/#{trace_run_id}"
  end

  def as_json_public
    {
      id: id,
      role: role,
      content: content,
      agent: agent,
      citations: citations,
      feedback: feedback&.as_json_public,
      created_at: created_at
    }
  end
end
