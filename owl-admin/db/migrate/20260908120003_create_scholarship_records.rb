class CreateScholarshipRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :scholarship_records do |t|
      t.references :source, foreign_key: true

      # Wire fields — mirror owl-api's ScholarshipIngest contract.
      t.string :source_url, null: false
      t.string :external_id
      t.string :title, null: false
      t.string :provider, null: false
      t.string :country, null: false, default: "CO"
      t.jsonb :fields, null: false, default: []
      t.jsonb :levels, null: false, default: []
      t.string :funding_type
      t.text :amount_note
      t.text :deadline
      t.text :eligibility_text
      t.text :body_markdown, null: false
      t.string :content_hash, null: false

      # Sync state with owl-api.
      t.string :owl_api_scholarship_id
      t.string :pushed_content_hash
      t.datetime :last_pushed_at
      t.string :last_push_status
      t.text :last_push_error

      t.timestamps
    end

    add_index :scholarship_records, :source_url, unique: true
  end
end
