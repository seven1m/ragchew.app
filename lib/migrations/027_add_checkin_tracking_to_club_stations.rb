class AddCheckinTrackingToClubStations < ActiveRecord::Migration[7.0]
  def change
    add_column :club_stations, :first_check_in, :datetime
    add_column :club_stations, :last_check_in, :datetime
    add_column :club_stations, :check_in_count, :integer, default: 0, null: false
  end
end
