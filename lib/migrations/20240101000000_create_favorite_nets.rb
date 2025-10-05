class CreateFavoriteNets < ActiveRecord::Migration[7.0]
  def change
    create_table :favorite_nets do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }
      t.string :net_name, null: false
      t.timestamps
    end

    add_index :favorite_nets, [:user_id, :net_name], unique: true
  end
end
