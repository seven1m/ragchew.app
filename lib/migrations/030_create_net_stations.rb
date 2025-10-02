class CreateNetStations < ActiveRecord::Migration[7.0]
  def change
    create_table :net_stations do |t|
      t.string :net_name, null: false
      t.string :call_sign, null: false
      t.datetime :first_check_in
      t.datetime :last_check_in
      t.integer :check_in_count, default: 0, null: false
      t.timestamps

      t.index %i[net_name call_sign], unique: true
    end
  end
end
