class StoreMoreStationInfo < ActiveRecord::Migration[7.0]
  def change
    change_table :stations do |t|
      t.string :first_name
      t.string :last_name
      t.string :grid_square
      t.string :street
      t.string :city
      t.string :state
      t.string :zip
      t.string :county
      t.string :country
      t.string :dxcc
      t.rename :image_expires_at, :expires_at
      t.boolean :not_found, default: false
    end
  end
end
