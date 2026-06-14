# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Seed admin (plan §4.7, D-tenancy): the deployer is the instance super-user.
# Created with a RANDOM password (never hardcoded) — claim the account via
# password reset on first login. Idempotent.
admin = User.find_or_create_by!(email_address: "admin@example.com") do |u|
  u.password = SecureRandom.base58(24)
  u.role = "admin"
  u.verified_at = Time.current
end
admin.update!(role: "admin") unless admin.admin?

# M1 seed: a sample subject/lesson/items so the Library is not empty in
# development, now owned by the seed admin (who keeps the full personal baseline).
# Idempotent.
subject = Subject.find_or_create_by!(name: "Sample Subject") do |s|
  s.description = "A starter subject created by db:seed."
  s.position = 0
  s.user = admin
end

lesson = subject.lessons.find_or_create_by!(title: "Sample Lesson") do |l|
  l.body = "A few example items to try the review loop later."
  l.position = 0
end

[
  [ "Capital of France?", "Paris" ],
  [ "2 + 2 = ?", "4" ],
  [ "Author of \"1984\"?", "George Orwell" ]
].each do |prompt, answer|
  lesson.items.find_or_create_by!(prompt: prompt) do |item|
    item.answer = answer
    # item_type defaults to free_recall; state defaults to learning.
  end
end
