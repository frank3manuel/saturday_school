require "test_helper"

class UserTest < ActiveSupport::TestCase
  def valid_attrs(overrides = {})
    { email_address: "person@example.com", password: "supersecret" }.merge(overrides)
  end

  test "valid with email and a password of at least 8 characters" do
    assert User.new(valid_attrs).valid?
  end

  test "requires an email address" do
    user = User.new(valid_attrs(email_address: nil))
    assert_not user.valid?
    assert_includes user.errors[:email_address], "can't be blank"
  end

  test "rejects a malformed email" do
    assert_not User.new(valid_attrs(email_address: "not-an-email")).valid?
  end

  test "normalizes email to stripped lowercase" do
    user = User.create!(valid_attrs(email_address: "  Person@Example.COM "))
    assert_equal "person@example.com", user.email_address
  end

  test "email uniqueness is case-insensitive" do
    User.create!(valid_attrs(email_address: "dup@example.com"))
    dup = User.new(valid_attrs(email_address: "DUP@example.com"))
    assert_not dup.valid?
    assert_includes dup.errors[:email_address], "has already been taken"
  end

  test "find_by normalizes the lookup address" do
    user = User.create!(valid_attrs(email_address: "lookup@example.com"))
    assert_equal user, User.find_by(email_address: "LOOKUP@EXAMPLE.COM")
  end

  test "requires a password of at least 8 characters" do
    user = User.new(valid_attrs(password: "short"))
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 8 characters)"
  end

  test "has_secure_password hashes and authenticates" do
    user = User.create!(valid_attrs(password: "correcthorse"))
    assert user.authenticate("correcthorse")
    assert_not user.authenticate("wrong")
    assert_not_equal "correcthorse", user.password_digest
  end

  test "authenticate_by finds and verifies in constant time" do
    user = User.create!(valid_attrs(email_address: "auth@example.com", password: "correcthorse"))
    assert_equal user, User.authenticate_by(email_address: "auth@example.com", password: "correcthorse")
    assert_nil User.authenticate_by(email_address: "auth@example.com", password: "nope")
    assert_nil User.authenticate_by(email_address: "missing@example.com", password: "whatever")
  end

  test "role defaults to student and exposes enum predicates" do
    user = User.create!(valid_attrs)
    assert user.student?
    assert_equal "student", user.role
  end

  test "role can be teacher or admin" do
    admin = User.create!(valid_attrs(email_address: "a@example.com", role: :admin))
    assert admin.admin?
  end

  test "a bogus role is rejected by the DB check constraint" do
    user = User.new(valid_attrs(email_address: "bogus@example.com"))
    assert_raises(ArgumentError) { user.role = "superuser" }
  end

  test "password reset token round-trips" do
    user = User.create!(valid_attrs(email_address: "reset@example.com"))
    token = user.generate_token_for(:password_reset)
    assert_equal user, User.find_by_token_for(:password_reset, token)
  end

  test "password reset token expires after 15 minutes" do
    user = User.create!(valid_attrs(email_address: "expire@example.com"))
    token = user.generate_token_for(:password_reset)
    travel 16.minutes do
      assert_nil User.find_by_token_for(:password_reset, token)
    end
  end

  test "changing the password invalidates an outstanding reset token" do
    user = User.create!(valid_attrs(email_address: "rotate@example.com", password: "oldpassword"))
    token = user.generate_token_for(:password_reset)
    user.update!(password: "newpassword")
    assert_nil User.find_by_token_for(:password_reset, token)
  end

  test "destroying a user cascades to owned content" do
    user = User.create!(valid_attrs(email_address: "cascade@example.com"))
    subject = user.subjects.create!(name: "Owned")
    lesson = subject.lessons.create!(title: "L")
    item = lesson.items.create!(prompt: "Q", answer: "A")
    user.attempts.create!(item: item, grade: :good, correct: true, reviewed_at: Time.current)
    user.quiz_sessions.create!(started_at: Time.current)

    assert_difference -> { Subject.count } => -1, -> { Lesson.count } => -1,
                      -> { Item.count } => -1, -> { Attempt.count } => -1,
                      -> { QuizSession.count } => -1 do
      user.destroy
    end
  end
end
