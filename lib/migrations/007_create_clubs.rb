class CreateClubs < ActiveRecord::Migration[7.0]
  def change
    create_table :clubs do |t|
      t.string :name, null: false
      t.string :full_name
      t.text :description
      t.string :profile_url
      t.string :about_url
      t.string :logo_url
      t.datetime :logo_updated_at
      t.integer :expiration_time
      t.integer :current_net_expiration_time
      t.text :net_patterns
      t.text :net_list
      t.timestamps

      t.index :name, unique: true
      t.index :full_name
    end

    change_table :servers do |t|
      t.string :club_info_list_url
    end

    change_table :nets do |t|
      t.integer :club_id
      t.index :club_id
    end

    change_table :closed_nets do |t|
      t.integer :club_id
      t.index :club_id
    end
  end
end
