require "test_helper"

class Admin::AnnotationsControllerTest < ActionDispatch::IntegrationTest
  include SignedInAdmin

  setup do
    student = User.create!(email: "student@example.com", password: "password123")
    conversation = student.conversations.create!
    @message = conversation.messages.create!(role: :assistant, content: "respuesta a anotar")
  end

  test "create stores a verdict and the ideal reply, attributed to the admin" do
    post admin_message_annotation_path(@message), params: { annotation: {
      verdict: "bad", ideal_response: "Debería mencionar las fechas.", note: "faltan datos"
    } }

    annotation = @message.reload.annotation
    assert_equal "bad", annotation.verdict
    assert_equal "Debería mencionar las fechas.", annotation.ideal_response
    assert_equal @admin.id, annotation.annotator_id
  end

  test "update overwrites the existing annotation" do
    @message.create_annotation!(verdict: :bad, annotator: @admin)

    patch admin_message_annotation_path(@message), params: { annotation: { verdict: "good" } }

    assert_equal "good", @message.reload.annotation.verdict
  end

  test "destroy removes it" do
    @message.create_annotation!(verdict: :good, annotator: @admin)

    delete admin_message_annotation_path(@message)

    assert_nil @message.reload.annotation
  end

  test "an invalid verdict is rejected" do
    assert_raises(ArgumentError) do
      post admin_message_annotation_path(@message), params: { annotation: { verdict: "meh" } }
    end
  end
end
