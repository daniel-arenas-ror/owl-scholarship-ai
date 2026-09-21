require "rails_helper"

RSpec.describe "Admin annotations", type: :request do
  include_context "signed in admin"

  let(:message) { create(:message, :assistant, content: "respuesta a anotar") }

  it "creates a verdict and the ideal reply, attributed to the admin" do
    post admin_message_annotation_path(message), params: { annotation: {
      verdict: "bad", ideal_response: "Debería mencionar las fechas.", note: "faltan datos"
    } }

    annotation = message.reload.annotation
    expect(annotation.verdict).to eq("bad")
    expect(annotation.ideal_response).to eq("Debería mencionar las fechas.")
    expect(annotation.annotator_id).to eq(admin.id)
  end

  it "overwrites the existing annotation on update" do
    message.create_annotation!(verdict: :bad, annotator: admin)

    patch admin_message_annotation_path(message), params: { annotation: { verdict: "good" } }

    expect(message.reload.annotation.verdict).to eq("good")
  end

  it "removes it on destroy" do
    message.create_annotation!(verdict: :good, annotator: admin)

    delete admin_message_annotation_path(message)

    expect(message.reload.annotation).to be_nil
  end

  it "rejects an invalid verdict" do
    expect do
      post admin_message_annotation_path(message), params: { annotation: { verdict: "meh" } }
    end.to raise_error(ArgumentError)
  end
end
