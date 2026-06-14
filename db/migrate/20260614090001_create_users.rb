class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.datetime :verified_at
      # Exactly one role per account (plan §4.6): scalar enum, NOT NULL, default
      # student, with a DB CHECK so the column can never hold a bogus value even
      # if the application layer is bypassed. Roles aren't *enforced* until M6,
      # but the column ships now.
      t.string :role, null: false, default: "student"

      t.timestamps
    end

    # Case-insensitive uniqueness is enforced by normalizing the address to
    # lowercase on the model (plan §4.4) plus this unique index — SQLite has no
    # citext.
    add_index :users, :email_address, unique: true

    add_check_constraint :users, "role IN ('student', 'teacher', 'admin')", name: "users_role_check"
  end
end
