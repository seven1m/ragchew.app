class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :call_sign, null: false
      t.string :first_name
      t.string :last_name
      t.string :image, limit: 1000
      t.datetime :last_signed_in_at
      t.timestamps

      t.index :call_sign
    end
  end
end
