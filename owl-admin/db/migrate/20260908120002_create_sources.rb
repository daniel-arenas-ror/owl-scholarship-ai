class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :name, null: false
      t.string :host, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :last_scraped_at
      t.string :last_status
      t.text :last_error

      t.timestamps
    end

    add_index :sources, :host, unique: true
  end
end
