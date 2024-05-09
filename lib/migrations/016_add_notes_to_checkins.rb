class AddNotesToCheckins < ActiveRecord::Migration[7.0]
  def change
    change_table :checkins do |t|
      t.string :notes, limit: 500
    end
  end
end
