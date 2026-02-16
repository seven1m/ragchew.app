class CreateApiTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, limit: 64, null: false
      t.datetime :last_used_at
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false

      t.index :token, unique: true
    end
  end
end
