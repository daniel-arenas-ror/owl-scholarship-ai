require "rails_helper"

RSpec.describe Features do
  after { Flipper.enable(Features::AI_SCHOLARSHIP_AGENT) } # restore the default

  it "ai_scholarship_agent? reflects the flipper gate" do
    Flipper.disable(described_class::AI_SCHOLARSHIP_AGENT)
    expect(described_class.ai_scholarship_agent?).to be(false)

    Flipper.enable(described_class::AI_SCHOLARSHIP_AGENT)
    expect(described_class.ai_scholarship_agent?).to be(true)
  end
end
