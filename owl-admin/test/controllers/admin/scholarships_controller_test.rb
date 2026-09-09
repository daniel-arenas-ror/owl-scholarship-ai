require "test_helper"

class Admin::ScholarshipsControllerTest < ActionDispatch::IntegrationTest
  include SignedInAdmin

  setup do
    @record = ScholarshipRecord.upsert_from_payload(
      "source_url" => "https://beca.gov.co/x",
      "title" => "Beca Original",
      "provider" => "Proveedor",
      "country" => "CO",
      "fields" => [],
      "levels" => [ "maestría" ],
      "body_markdown" => "Cuerpo original con bastante texto de relleno."
    )
  end

  test "index lists records and can filter to pending" do
    get admin_scholarships_path
    assert_response :success
    assert_match "Beca Original", response.body

    get admin_scholarships_path(filter: "pending")
    assert_response :success
    assert_match "Beca Original", response.body # never pushed -> pending
  end

  test "update edits wire fields, splits the list inputs, and marks it pending" do
    before_hash = @record.content_hash

    patch admin_scholarship_path(@record), params: { scholarship_record: {
      title: "Beca Editada",
      levels_text: "maestría\ndoctorado",
      fields_text: "Ingeniería, Ciencias",
      body_markdown: @record.body_markdown
    } }

    assert_redirected_to admin_scholarship_path(@record)
    @record.reload
    assert_equal "Beca Editada", @record.title
    assert_equal %w[maestría doctorado], @record.levels
    assert_equal [ "Ingeniería", "Ciencias" ], @record.fields
    assert_not_equal before_hash, @record.content_hash
  end

  test "push sends to owl-api and reports the action" do
    stub_ingest(scholarship_id: "9", chunks: 3, action: "updated") do
      post push_admin_scholarship_path(@record)
    end

    assert_redirected_to admin_scholarship_path(@record)
    assert_equal "updated", @record.reload.last_push_status
    assert_not @record.pending_push?
  end

  test "push surfaces an owl-api error as a flash alert" do
    stub_ingest_raising("422 bad payload") do
      post push_admin_scholarship_path(@record)
    end

    assert_redirected_to admin_scholarship_path(@record)
    follow_redirect!
    assert_match "owl-api rechazó", response.body
    assert_equal "error", @record.reload.last_push_status
  end

  test "requires an admin" do
    sign_out @admin
    get admin_scholarships_path
    assert_redirected_to new_user_session_path
  end

  private

  def stub_ingest(result)
    original = OwlApiClient.method(:ingest)
    OwlApiClient.define_singleton_method(:ingest) { |_payload| result }
    yield
  ensure
    OwlApiClient.define_singleton_method(:ingest, original)
  end

  def stub_ingest_raising(message)
    original = OwlApiClient.method(:ingest)
    OwlApiClient.define_singleton_method(:ingest) { |_payload| raise OwlApiClient::Error, message }
    yield
  ensure
    OwlApiClient.define_singleton_method(:ingest, original)
  end
end
