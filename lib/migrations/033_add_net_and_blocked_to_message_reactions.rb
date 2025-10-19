class AddNetAndBlockedToMessageReactions < ActiveRecord::Migration[7.0]
  def change
    change_table :message_reactions do |t|
      t.integer :net_id, null: false
      t.boolean :blocked, default: false, null: false
    end
  end
end
