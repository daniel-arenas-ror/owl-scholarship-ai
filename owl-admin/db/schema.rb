# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_17_142429) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "annotations", force: :cascade do |t|
    t.bigint "annotator_id", null: false
    t.datetime "created_at", null: false
    t.text "ideal_response"
    t.bigint "message_id", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.integer "verdict", null: false
    t.index ["annotator_id"], name: "index_annotations_on_annotator_id"
    t.index ["message_id"], name: "index_annotations_on_message_id", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "feedbacks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.integer "rating", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_feedbacks_on_message_id", unique: true
  end

  create_table "flipper_features", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.string "agent"
    t.jsonb "citations", default: [], null: false
    t.text "content", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "generation", default: {}, null: false
    t.integer "role", default: 0, null: false
    t.string "trace_run_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "host", null: false
    t.text "last_error"
    t.datetime "last_scraped_at"
    t.string "last_status"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["host"], name: "index_sources_on_host", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "degrees", default: [], null: false, array: true
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "full_name"
    t.string "phone"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "annotations", "messages"
  add_foreign_key "annotations", "users", column: "annotator_id"
  add_foreign_key "conversations", "users"
  add_foreign_key "feedbacks", "messages"
  add_foreign_key "messages", "conversations"
end
