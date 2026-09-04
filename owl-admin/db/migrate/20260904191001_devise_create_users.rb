# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      ## Database authenticatable
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      # student (default) or admin — the Phase 5 admin dashboards check this.
      t.integer :role, null: false, default: 0

      t.timestamps null: false
    end

    add_index :users, :email, unique: true
  end
end
