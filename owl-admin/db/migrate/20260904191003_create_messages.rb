class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.text :content, null: false
      t.string :agent
      t.jsonb :citations, null: false, default: []

      t.timestamps
    end
  end
end
