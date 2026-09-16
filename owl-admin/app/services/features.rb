# Central place for feature-flag names, backed by the `flipper` gem (see
# config/initializers/flipper.rb for the storage adapter). Toggle from
# /admin/flipper, or the console:
#
#   Flipper.enable(Features::AI_SCHOLARSHIP_AGENT)
#   Flipper.disable(Features::AI_SCHOLARSHIP_AGENT)
module Features
  # true  (default): the chat agent — owl-web's Chat screen, sending each turn
  #                  through owl-api's LangGraph agent (OpenAI calls included).
  # false: owl-web shows a plain scholarship list + a search bar instead, and
  #        the message-send endpoint refuses to call owl-api — useful to cut
  #        OpenAI cost, or to A/B the "just search" experience.
  AI_SCHOLARSHIP_AGENT = :ai_scholarship_agent

  def self.ai_scholarship_agent?
    Flipper.enabled?(AI_SCHOLARSHIP_AGENT)
  end
end
