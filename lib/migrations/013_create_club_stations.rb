class CreateClubStations < ActiveRecord::Migration[7.0]
  def change
    create_table :club_stations do |t|
      t.integer :club_id, null: false
      t.string :call_sign, null: false
      t.string :preferred_name, limit: 50
      t.string :notes, limit: 500
      t.timestamps

      t.index %i[club_id call_sign], unique: true
    end
  end
end
