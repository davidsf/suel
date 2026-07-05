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

ActiveRecord::Schema[8.1].define(version: 2026_07_05_105157) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "boards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "game_map_id", null: false
    t.json "grid"
    t.integer "height"
    t.string "image_filename"
    t.string "name"
    t.integer "position", default: 0, null: false
    t.boolean "reversible", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["game_map_id"], name: "index_boards_on_game_map_id"
  end

  create_table "decks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "game_map_id", null: false
    t.integer "height"
    t.string "name"
    t.string "owning_board"
    t.json "settings", default: {}
    t.datetime "updated_at", null: false
    t.integer "width"
    t.integer "x"
    t.integer "y"
    t.index ["game_map_id"], name: "index_decks_on_game_map_id"
  end

  create_table "game_events", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "game_id", null: false
    t.string "kind", default: "roll", null: false
    t.json "payload", default: {}
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["game_id", "created_at"], name: "index_game_events_on_game_id_and_created_at"
    t.index ["game_id"], name: "index_game_events_on_game_id"
    t.index ["user_id"], name: "index_game_events_on_user_id"
  end

  create_table "game_maps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "game_module_id", null: false
    t.string "kind", default: "map", null: false
    t.string "name"
    t.integer "position", default: 0, null: false
    t.json "settings", default: {}
    t.string "side"
    t.datetime "updated_at", null: false
    t.index ["game_module_id"], name: "index_game_maps_on_game_module_id"
  end

  create_table "game_modules", force: :cascade do |t|
    t.json "build_tree"
    t.json "charts", default: []
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.string "name"
    t.json "parse_warnings", default: []
    t.string "progress_note"
    t.string "slug", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "vassal_version"
    t.string "version"
    t.index ["slug"], name: "index_game_modules_on_slug", unique: true
  end

  create_table "game_pieces", force: :cascade do |t|
    t.integer "board_id"
    t.datetime "created_at", null: false
    t.integer "deck_id"
    t.integer "deck_position"
    t.integer "game_id", null: false
    t.integer "game_map_id"
    t.string "gpid"
    t.string "hand_side"
    t.string "name"
    t.json "traits", default: []
    t.text "type_string"
    t.datetime "updated_at", null: false
    t.integer "x"
    t.integer "y"
    t.integer "z_order", default: 0, null: false
    t.index ["board_id"], name: "index_game_pieces_on_board_id"
    t.index ["deck_id"], name: "index_game_pieces_on_deck_id"
    t.index ["game_id", "deck_id"], name: "index_game_pieces_on_game_id_and_deck_id"
    t.index ["game_id", "game_map_id"], name: "index_game_pieces_on_game_id_and_game_map_id"
    t.index ["game_id", "hand_side"], name: "index_game_pieces_on_game_id_and_hand_side"
    t.index ["game_id"], name: "index_game_pieces_on_game_id"
    t.index ["game_map_id"], name: "index_game_pieces_on_game_map_id"
  end

  create_table "games", force: :cascade do |t|
    t.json "board_setup", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "creator_id", null: false
    t.integer "game_module_id", null: false
    t.string "name", null: false
    t.json "properties", default: {}, null: false
    t.integer "scenario_id", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_games_on_creator_id"
    t.index ["game_module_id"], name: "index_games_on_game_module_id"
    t.index ["scenario_id"], name: "index_games_on_scenario_id"
  end

  create_table "piece_definitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "deck_id"
    t.integer "game_module_id", null: false
    t.string "gpid"
    t.string "name"
    t.json "palette_path", default: []
    t.integer "position", default: 0, null: false
    t.string "slot_kind", default: "piece", null: false
    t.text "state_string"
    t.json "traits", default: []
    t.text "type_string"
    t.datetime "updated_at", null: false
    t.index ["deck_id"], name: "index_piece_definitions_on_deck_id"
    t.index ["game_module_id", "gpid"], name: "index_piece_definitions_on_game_module_id_and_gpid"
    t.index ["game_module_id"], name: "index_piece_definitions_on_game_module_id"
  end

  create_table "players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "game_id", null: false
    t.string "side", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["game_id", "side"], name: "index_players_on_game_id_and_side", unique: true
    t.index ["game_id", "user_id"], name: "index_players_on_game_id_and_user_id", unique: true
    t.index ["game_id"], name: "index_players_on_game_id"
    t.index ["user_id"], name: "index_players_on_user_id"
  end

  create_table "prototypes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "game_module_id", null: false
    t.string "name", null: false
    t.text "state_string"
    t.text "type_string"
    t.datetime "updated_at", null: false
    t.index ["game_module_id", "name"], name: "index_prototypes_on_game_module_id_and_name", unique: true
    t.index ["game_module_id"], name: "index_prototypes_on_game_module_id"
  end

  create_table "scenario_pieces", force: :cascade do |t|
    t.integer "board_id"
    t.datetime "created_at", null: false
    t.integer "game_map_id"
    t.string "gpid"
    t.string "map_identifier"
    t.string "name"
    t.string "piece_uid"
    t.integer "scenario_id", null: false
    t.json "state", default: {}
    t.json "traits", default: []
    t.text "type_string"
    t.datetime "updated_at", null: false
    t.integer "x"
    t.integer "y"
    t.integer "z_order", default: 0, null: false
    t.index ["board_id"], name: "index_scenario_pieces_on_board_id"
    t.index ["game_map_id"], name: "index_scenario_pieces_on_game_map_id"
    t.index ["scenario_id"], name: "index_scenario_pieces_on_scenario_id"
  end

  create_table "scenarios", force: :cascade do |t|
    t.json "board_setup", default: {}
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.integer "game_module_id", null: false
    t.string "kind", default: "vsav", null: false
    t.string "name"
    t.string "source_filename"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["game_module_id"], name: "index_scenarios_on_game_module_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "boards", "game_maps"
  add_foreign_key "decks", "game_maps"
  add_foreign_key "game_events", "games"
  add_foreign_key "game_events", "users"
  add_foreign_key "game_maps", "game_modules"
  add_foreign_key "game_pieces", "boards"
  add_foreign_key "game_pieces", "decks"
  add_foreign_key "game_pieces", "game_maps"
  add_foreign_key "game_pieces", "games"
  add_foreign_key "games", "game_modules"
  add_foreign_key "games", "scenarios"
  add_foreign_key "games", "users", column: "creator_id"
  add_foreign_key "piece_definitions", "decks"
  add_foreign_key "piece_definitions", "game_modules"
  add_foreign_key "players", "games"
  add_foreign_key "players", "users"
  add_foreign_key "prototypes", "game_modules"
  add_foreign_key "scenario_pieces", "boards"
  add_foreign_key "scenario_pieces", "game_maps"
  add_foreign_key "scenario_pieces", "scenarios"
  add_foreign_key "scenarios", "game_modules"
  add_foreign_key "sessions", "users"
end
