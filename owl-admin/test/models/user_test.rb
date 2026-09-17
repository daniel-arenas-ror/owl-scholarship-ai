require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires a unique email" do
    User.create!(email: "dup@example.com", password: "password123")
    dup = User.new(email: "dup@example.com", password: "password123")

    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end

  test "defaults to the student role" do
    user = User.create!(email: "student@example.com", password: "password123")
    assert user.student?
  end

  test "as_json_public never leaks the password" do
    user = User.create!(email: "safe@example.com", password: "password123")
    assert_equal({ id: user.id, email: user.email, role: "student" }, user.as_json_public)
  end

  test "profile_json exposes the agent-collected fields plus the account email" do
    user = User.create!(email: "profile@example.com", password: "password123",
      full_name: "Maria Lopez", phone: "3001234567", degrees: [ "Ingeniería" ])

    assert_equal(
      { full_name: "Maria Lopez", email: "profile@example.com", phone: "3001234567", degrees: [ "Ingeniería" ] },
      user.profile_json
    )
  end

  test "degrees defaults to an empty array" do
    user = User.create!(email: "nodegree@example.com", password: "password123")
    assert_equal [], user.degrees
  end
end
