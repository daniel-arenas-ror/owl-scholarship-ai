class CreateAnnotations < ActiveRecord::Migration[8.1]
  def change
    create_table :annotations do |t|
      t.references :message, null: false, foreign_key: true, index: { unique: true }
      t.references :annotator, null: false, foreign_key: { to_table: :users }
      t.integer :verdict, null: false
      t.text :ideal_response
      t.text :note

      t.timestamps
    end
  end
end
