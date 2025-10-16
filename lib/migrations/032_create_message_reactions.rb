class CreateMessageReactions < ActiveRecord::Migration[7.0]
  def change
    create_table :message_reactions, options: 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci' do |t|
      t.integer :message_id, null: false
      t.string :reaction, null: false
      t.string :call_sign, null: false
      t.string :name
      t.integer :user_id
      t.timestamps
    end

    add_index :message_reactions, :message_id
    add_index :message_reactions, [:message_id, :call_sign, :reaction], unique: true
  end
end
