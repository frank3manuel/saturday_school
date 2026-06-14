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

ActiveRecord::Schema[7.2].define(version: 2026_06_14_090009) do
  create_table "assignments", force: :cascade do |t|
    t.integer "cohort_id", null: false
    t.integer "lesson_id", null: false
    t.integer "assigned_by", null: false
    t.datetime "assigned_at", null: false
    t.datetime "withdrawn_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_by"], name: "index_assignments_on_assigned_by"
    t.index ["cohort_id", "lesson_id"], name: "index_assignments_on_cohort_id_and_lesson_id", unique: true
    t.index ["cohort_id"], name: "index_assignments_on_cohort_id"
    t.index ["lesson_id"], name: "index_assignments_on_lesson_id"
  end

  create_table "attempts", force: :cascade do |t|
    t.integer "item_id", null: false
    t.integer "user_id", null: false
    t.integer "quiz_session_id"
    t.integer "grade", default: 0, null: false
    t.boolean "correct", null: false
    t.datetime "reviewed_at", null: false
    t.integer "interval_before"
    t.integer "interval_after"
    t.integer "response_latency_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_attempts_on_item_id"
    t.index ["quiz_session_id"], name: "index_attempts_on_quiz_session_id"
    t.index ["user_id", "item_id"], name: "index_attempts_on_user_id_and_item_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.integer "actor_id"
    t.integer "target_user_id"
    t.string "action", null: false
    t.string "target_email"
    t.text "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_events_on_action"
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["target_user_id"], name: "index_audit_events_on_target_user_id"
  end

  create_table "cohorts", force: :cascade do |t|
    t.integer "teacher_id", null: false
    t.string "name", null: false
    t.string "join_code", null: false
    t.text "description"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["join_code"], name: "index_cohorts_on_join_code", unique: true
    t.index ["teacher_id"], name: "index_cohorts_on_teacher_id"
  end

  create_table "enrollments", force: :cascade do |t|
    t.integer "cohort_id", null: false
    t.integer "user_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "joined_at", null: false
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cohort_id", "status"], name: "index_enrollments_on_cohort_id_and_status"
    t.index ["cohort_id", "user_id"], name: "index_enrollments_on_cohort_id_and_user_id", unique: true
    t.index ["cohort_id"], name: "index_enrollments_on_cohort_id"
    t.index ["user_id"], name: "index_enrollments_on_user_id"
    t.check_constraint "status IN ('active', 'left', 'removed')", name: "enrollments_status_check"
  end

  create_table "items", force: :cascade do |t|
    t.integer "lesson_id", null: false
    t.text "prompt", null: false
    t.text "answer", null: false
    t.integer "item_type", default: 0, null: false
    t.boolean "suspended", default: false, null: false
    t.datetime "due_at"
    t.integer "interval_days", default: 0, null: false
    t.integer "box", default: 0, null: false
    t.integer "streak", default: 0, null: false
    t.integer "repetitions", default: 0, null: false
    t.integer "lapses", default: 0, null: false
    t.datetime "last_reviewed_at"
    t.datetime "mastered_at"
    t.integer "state", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id"], name: "index_items_on_lesson_id"
    t.index ["mastered_at"], name: "index_items_on_mastered_at"
    t.index ["suspended", "due_at"], name: "index_items_on_suspended_and_due_at"
  end

  create_table "lessons", force: :cascade do |t|
    t.integer "subject_id", null: false
    t.string "title", null: false
    t.text "body"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_id"], name: "index_lessons_on_subject_id"
  end

  create_table "quiz_sessions", force: :cascade do |t|
    t.integer "subject_id"
    t.integer "user_id", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "planned_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_id"], name: "index_quiz_sessions_on_subject_id"
    t.index ["user_id"], name: "index_quiz_sessions_on_user_id"
  end

  create_table "review_states", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "item_id", null: false
    t.boolean "suspended", default: false, null: false
    t.datetime "due_at"
    t.integer "interval_days", default: 0, null: false
    t.integer "box", default: 0, null: false
    t.integer "streak", default: 0, null: false
    t.integer "repetitions", default: 0, null: false
    t.integer "lapses", default: 0, null: false
    t.datetime "last_reviewed_at"
    t.datetime "mastered_at"
    t.integer "state", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_review_states_on_item_id"
    t.index ["user_id", "item_id"], name: "index_review_states_on_user_id_and_item_id", unique: true
    t.index ["user_id", "suspended", "due_at"], name: "index_review_states_on_user_id_and_suspended_and_due_at"
    t.index ["user_id"], name: "index_review_states_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "token", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "subjects", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "user_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_subjects_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "verified_at"
    t.string "role", default: "student", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.check_constraint "role IN ('student', 'teacher', 'admin')", name: "users_role_check"
  end

  add_foreign_key "assignments", "cohorts", on_delete: :cascade
  add_foreign_key "assignments", "lessons", on_delete: :cascade
  add_foreign_key "assignments", "users", column: "assigned_by", on_delete: :restrict
  add_foreign_key "attempts", "items", on_delete: :cascade
  add_foreign_key "attempts", "quiz_sessions", on_delete: :nullify
  add_foreign_key "attempts", "users", on_delete: :cascade
  add_foreign_key "audit_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "audit_events", "users", column: "target_user_id", on_delete: :nullify
  add_foreign_key "cohorts", "users", column: "teacher_id", on_delete: :restrict
  add_foreign_key "enrollments", "cohorts", on_delete: :cascade
  add_foreign_key "enrollments", "users", on_delete: :cascade
  add_foreign_key "items", "lessons", on_delete: :cascade
  add_foreign_key "lessons", "subjects", on_delete: :cascade
  add_foreign_key "quiz_sessions", "subjects", on_delete: :cascade
  add_foreign_key "quiz_sessions", "users", on_delete: :cascade
  add_foreign_key "review_states", "items", on_delete: :cascade
  add_foreign_key "review_states", "users", on_delete: :cascade
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "subjects", "users", on_delete: :cascade
end
