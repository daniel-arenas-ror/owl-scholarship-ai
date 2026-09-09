require "test_helper"

class ScholarshipRecordTest < ActiveSupport::TestCase
  def payload(overrides = {})
    {
      "source" => "beca.gov.co",
      "source_url" => "https://beca.gov.co/x",
      "external_id" => nil,
      "title" => "Beca X",
      "provider" => "Proveedor X",
      "country" => "CO",
      "fields" => [ "Ingeniería" ],
      "levels" => [ "maestría" ],
      "body_markdown" => "Cuerpo de la beca X con suficiente texto."
    }.merge(overrides)
  end

  test "upsert_from_payload creates the record and its source" do
    record = ScholarshipRecord.upsert_from_payload(payload)

    assert record.persisted?
    assert_equal "beca.gov.co", record.source.host
    assert_equal "Beca X", record.title
    assert record.content_hash.present?
    assert record.pending_push?, "a fresh record has never been pushed"
  end

  test "upsert_from_payload updates the existing row for the same source_url" do
    ScholarshipRecord.upsert_from_payload(payload)
    record = ScholarshipRecord.upsert_from_payload(payload("title" => "Beca X (v2)"))

    assert_equal 1, ScholarshipRecord.count
    assert_equal "Beca X (v2)", record.title
  end

  test "editing any wire field changes content_hash" do
    record = ScholarshipRecord.upsert_from_payload(payload)
    before = record.content_hash

    record.update!(deadline: "Marzo 2027")
    assert_not_equal before, record.content_hash
  end

  test "push_to_owl_api! records sync state on success" do
    record = ScholarshipRecord.upsert_from_payload(payload)

    stub_ingest(scholarship_id: "77", chunks: 4, action: "created") do
      record.push_to_owl_api!
    end

    assert_equal "77", record.owl_api_scholarship_id
    assert_equal "created", record.last_push_status
    assert_not record.pending_push?, "pushed_content_hash now matches"
    assert record.synced?
  end

  test "push_to_owl_api! records the error and re-raises" do
    record = ScholarshipRecord.upsert_from_payload(payload)

    error = assert_raises(OwlApiClient::Error) do
      stub_ingest_raising("owl-api down") { record.push_to_owl_api! }
    end
    assert_equal "owl-api down", error.message
    assert_equal "error", record.reload.last_push_status
    assert_equal "owl-api down", record.last_push_error
  end

  test "to_ingest_payload matches the owl-api contract keys" do
    record = ScholarshipRecord.upsert_from_payload(payload)
    keys = record.to_ingest_payload.keys

    assert_includes keys, "content_hash"
    assert_includes keys, "body_markdown"
    assert_includes keys, "source_url"
    assert_equal "beca.gov.co", record.to_ingest_payload["source"]
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
