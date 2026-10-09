class CreateZooTables < ActiveRecord::Migration[8.1]
  def change
    create_table :zoo_hops do |t|
      t.string :trace, limit: 36, null: false
      t.string :step, limit: 40, null: false
      t.string :detail, limit: 200
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.index [:trace, :step], unique: true
    end

    create_table :zoo_probes do |t|
      t.string :token, limit: 64, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.index :token, unique: true
    end
  end
end
