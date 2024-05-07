class CreateClubAdmins < ActiveRecord::Migration[7.0]
  def change
    create_table :club_admins do |t|
      t.integer :club_id, null: false
      t.integer :user_id, null: false
      t.integer :flags, default: 0, null: false
      t.timestamps

      t.index %i[club_id user_id], unique: true
    end
  end
end
