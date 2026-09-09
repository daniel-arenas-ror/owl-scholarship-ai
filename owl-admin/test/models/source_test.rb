require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "for_url finds or creates by host, stripping www" do
    a = Source.for_url("https://www.icetex.gov.co/becas/x")
    b = Source.for_url("https://icetex.gov.co/otra")

    assert_equal "icetex.gov.co", a.host
    assert_equal a.id, b.id
    assert_equal "icetex.gov.co", a.name
  end

  test "for_url returns nil for a junk url" do
    assert_nil Source.for_url("not a url")
  end

  test "record_scrape! stamps status" do
    source = Source.for_url("https://x.test/a")
    source.record_scrape!(status: "error", error: "boom")

    assert_equal "error", source.last_status
    assert_equal "boom", source.last_error
    assert_not source.healthy?
    assert_not_nil source.last_scraped_at
  end
end
