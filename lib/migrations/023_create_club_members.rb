class CreateClubMembers < ActiveRecord::Migration[7.0]
  def change
    create_table :club_members do |t|
      t.integer :club_id, null: false
      t.integer :user_id, null: false

      t.timestamps

      t.index %i[club_id user_id], unique: true
    end

    reversible do |direction|
      direction.up do
        Tables::ClubAdmin.find_each do |club_admin|
          next unless club_admin.net_logger?

          Tables::ClubMember.create!(
            club_id: club_admin.club_id,
            user_id: club_admin.user_id,
          )
        end
      end
    end
  end
end
