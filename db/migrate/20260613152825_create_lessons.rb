class CreateLessons < ActiveRecord::Migration[7.2]
  def change
    create_table :lessons do |t|
      # Every lesson belongs to a subject (plan §15 D1): NOT NULL + DB FK,
      # cascade on subject deletion. Ownership derives via subject (§4.5).
      t.references :subject, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :title, null: false
      t.text :body
      t.integer :position

      t.timestamps
    end
  end
end
