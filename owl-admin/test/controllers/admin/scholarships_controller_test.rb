require "test_helper"

class Admin::ScholarshipsControllerTest < ActionDispatch::IntegrationTest
  include SignedInAdmin

  setup do
    @scholarship = create_scholarship(
      source: "beca.gov.co",
      source_url: "https://beca.gov.co/x",
      title: "Beca Original",
      provider: "Proveedor",
      levels: [ "maestría" ]
    )
  end

  test "index lists scholarships from owl-api's table" do
    get admin_scholarships_path
    assert_response :success
    assert_match "Beca Original", response.body
  end

  test "show renders the scholarship" do
    get admin_scholarship_path(@scholarship)
    assert_response :success
    assert_match "Beca Original", response.body
    assert_match @scholarship.id.to_s, response.body
  end

  test "update sends the edited fields to owl-api's ingest endpoint" do
    with_stubbed_ingest({ scholarship_id: @scholarship.id.to_s, chunks: 4, action: "updated" }) do
      patch admin_scholarship_path(@scholarship), params: { scholarship: {
        title: "Beca Editada",
        deadline: "Marzo 2027",
        levels_text: "maestría\ndoctorado",
        fields_text: "Ingeniería, Ciencias",
        body_markdown: @scholarship.body_markdown
      } }
    end

    assert_redirected_to admin_scholarship_path(@scholarship)
    follow_redirect!
    assert_match "Enviado a owl-api (updated)", response.body

    # the payload owl-api received carries the edits (owl-api is the writer)
    assert_equal "Beca Editada", @ingested["title"]
    assert_equal "Marzo 2027", @ingested["deadline"]
    assert_equal %w[maestría doctorado], @ingested["levels"]
    assert_equal [ "Ingeniería", "Ciencias" ], @ingested["fields"]
    assert_nil @ingested["content_hash"] # owl-api computes it
  end

  test "a blank required field is rejected before calling owl-api" do
    with_stubbed_ingest(-> { flunk "ingest must not be called for an invalid edit" }) do
      patch admin_scholarship_path(@scholarship), params: { scholarship: { title: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "an owl-api error is shown on the edit form" do
    with_stubbed_ingest(-> { raise OwlApiClient::Error, "422 bad payload" }) do
      patch admin_scholarship_path(@scholarship), params: { scholarship: { title: "Nueva" } }
    end
    assert_response :unprocessable_entity
    assert_match "owl-api rechazó", response.body
  end

  test "requires an admin" do
    sign_out @admin
    get admin_scholarships_path
    assert_redirected_to new_user_session_path
  end

  private

  # Swap OwlApiClient.ingest for the block. `stub` is the result Hash to return
  # (payload captured in @ingested) or a callable run for its side effect.
  def with_stubbed_ingest(stub)
    original = OwlApiClient.method(:ingest)
    test = self
    OwlApiClient.define_singleton_method(:ingest) do |payload|
      next stub.call if stub.respond_to?(:call)

      test.instance_variable_set(:@ingested, payload)
      stub
    end
    yield
  ensure
    OwlApiClient.define_singleton_method(:ingest, original)
  end
end
