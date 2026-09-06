class CreateFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :feedbacks do |t|
      t.references :message, null: false, foreign_key: true, index: { unique: true }
      t.integer :rating, null: false
      t.text :reason

      t.timestamps
    end
  end
end
