class CreateBlockedStations < ActiveRecord::Migration[7.0]
  def change
    create_table :blocked_stations do |t|
      t.string :call_sign, null: false
      t.references :blocker, polymorphic: true, null: false
      t.timestamps
    end

    add_index :blocked_stations, [:blocker_type, :blocker_id]
  end
end
