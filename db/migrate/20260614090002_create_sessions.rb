class CreateSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      # An opaque, high-entropy token. The browser only ever holds this value in
      # a signed permanent cookie (plan §4.4); it is never JS-set.
      t.string :token, null: false
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :sessions, :token, unique: true
  end
end
