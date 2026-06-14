# Backfill ownership of all pre-auth content onto a single seed user (plan §4.7).
#
# Non-destructive and idempotent: creates one admin "deployer" account with a
# RANDOM password (never hardcoded — the owner claims it via password reset on
# first login), reparents any subject-less lessons into a per-user "Ungrouped"
# subject (every lesson already requires a subject per D1, so normally none),
# then stamps the orphaned subjects/quiz_sessions/attempts with that user.
#
# The `null: false` flip + FKs/indexes are a SEPARATE follow-up migration so a
# backfill bug can't wedge the schema change.
class BackfillUserOwnership < ActiveRecord::Migration[7.2]
  # Lightweight, migration-local models so the backfill is insulated from future
  # changes to the real model classes (validations, scopes, etc.).
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
    has_secure_password validations: false
  end

  def up
    # Idempotent: nothing to own → no seed user is created, re-runs are no-ops.
    return if orphan_content_absent?

    seed = find_or_create_seed_user
    reparent_loose_lessons(seed)

    say_with_time "stamping orphaned content with the seed user" do
      %w[subjects quiz_sessions attempts].each do |table|
        execute("UPDATE #{table} SET user_id = #{seed.id} WHERE user_id IS NULL")
      end
    end
  end

  def down
    # Non-reversible data backfill; leaving rows owned is safe. No-op so the
    # follow-up flip migration's rollback doesn't strand un-owned rows.
  end

  private

  def find_or_create_seed_user
    user = MigrationUser.find_by(email_address: seed_email)
    return user if user

    MigrationUser.create!(
      email_address: seed_email,
      password: SecureRandom.base58(32),
      role: "admin"
    )
  end

  # The deployer's claimable address. Overridable via ENV at deploy time.
  def seed_email
    ENV.fetch("SEED_USER_EMAIL", "owner@saturdayschool.local").strip.downcase
  end

  # Per D1 every lesson already belongs to a subject (NOT NULL subject_id), so
  # there should be no loose lessons. Guard defensively anyway: if any exist,
  # tuck them under an "Ungrouped" subject owned by the seed user.
  def reparent_loose_lessons(seed)
    loose = select_value("SELECT COUNT(*) FROM lessons WHERE subject_id IS NULL").to_i
    return if loose.zero?

    ungrouped_id = execute_insert_ungrouped_subject(seed.id)
    execute("UPDATE lessons SET subject_id = #{ungrouped_id} WHERE subject_id IS NULL")
  end

  def execute_insert_ungrouped_subject(user_id)
    now = quote(Time.current)
    execute(<<~SQL)
      INSERT INTO subjects (name, user_id, position, created_at, updated_at)
      VALUES ('Ungrouped', #{user_id}, 0, #{now}, #{now})
    SQL
    select_value("SELECT last_insert_rowid()").to_i
  end

  def orphan_content_absent?
    %w[subjects quiz_sessions attempts].all? do |table|
      select_value("SELECT COUNT(*) FROM #{table} WHERE user_id IS NULL").to_i.zero?
    end
  end
end
