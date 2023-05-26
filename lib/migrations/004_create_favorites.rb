class CreateFavorites < ActiveRecord::Migration[7.0]
  def change
    create_table :favorites do |t|
      t.references :user
      t.string :call_sign, null: false
      t.string :first_name
      t.string :last_name
      t.timestamps

      t.index %w[user_id call_sign], unique: true
    end
  end
end
