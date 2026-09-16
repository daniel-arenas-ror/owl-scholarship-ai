require "test_helper"

class FeaturesTest < ActiveSupport::TestCase
  test "ai_scholarship_agent? reflects the flipper gate" do
    Flipper.disable(Features::AI_SCHOLARSHIP_AGENT)
    assert_not Features.ai_scholarship_agent?

    Flipper.enable(Features::AI_SCHOLARSHIP_AGENT)
    assert Features.ai_scholarship_agent?
  ensure
    Flipper.enable(Features::AI_SCHOLARSHIP_AGENT) # restore the default
  end
end
