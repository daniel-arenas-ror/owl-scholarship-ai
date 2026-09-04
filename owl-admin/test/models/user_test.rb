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
end
