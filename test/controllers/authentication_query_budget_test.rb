require "test_helper"

# The session-lookup budget (plan §12): resolving the current user from the
# signed cookie must cost AT MOST ONE query per request. Current memoizes the
# resolved Session, so even pages that touch current_user several times don't
# re-query it.
class AuthenticationQueryBudgetTest < ActionDispatch::IntegrationTest
  test "an authenticated request runs at most one sessions lookup" do
    # Warm any one-time schema/setup queries first.
    get root_path
    assert_response :success

    session_queries = count_sql(/FROM\s+"sessions"/i) { get root_path }
    assert_operator session_queries, :<=, 1,
      "auth should add ≤1 sessions lookup/request, ran #{session_queries}"
  end

  private

  def count_sql(pattern)
    count = 0
    counter = lambda do |*, payload|
      count += 1 if payload[:sql].to_s.match?(pattern)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
