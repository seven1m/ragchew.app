class CreateStats < ActiveRecord::Migration[7.0]
  def change
    create_table :stats do |t|
      t.string :name, null: false
      t.datetime :period, null: false
      t.integer :value, null: false

      t.timestamps

      t.index %i[name period], unique: true
    end
  end
end
