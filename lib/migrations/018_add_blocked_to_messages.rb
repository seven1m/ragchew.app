class AddBlockedToMessages < ActiveRecord::Migration[7.0]
  def change
    change_table :messages do |t|
      t.boolean :blocked, default: false
    end
  end
end
