class CreateEstimateEntries < ActiveRecord::Migration
  def change
    create_table :estimate_entries do |t|
      t.integer   "project_id",    null: false
      t.integer   "user_id",       null: false
      t.integer   "issue_id",     limit:  4
      t.float     "hours",        limit: 24,   null: false
      t.string    "comments",     limit: 255
      t.integer   "activity_id",   null: false
      t.date      "spent_on",      null: false
      t.integer   "tyear",         null: false
      t.integer   "tweek",         null: false
      t.integer   "tmonth",        null: false
      t.datetime  "created_on",    null: false
      t.datetime  "updated_on",    null: false
    end
    add_index :estimate_entries, [:project_id], :name =>  :estimate_entries_project_id
    add_index :estimate_entries, [:issue_id],   :name =>  :estimate_entries_issue_id
  end
end

