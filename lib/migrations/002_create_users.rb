class CreateUsers < ActiveRecord::Migration[7.0]
  def up
    create_table :users do |t|
      t.string :call_sign, null: false
      t.string :first_name
      t.string :last_name
      t.string :hashed_password, null: false
      t.timestamps

      t.index :call_sign
    end
  end

  def down
    drop_table :users
  end
end
