class AddNumAndBlockedToMonitors < ActiveRecord::Migration[7.0]
  def change
    change_table :monitors do |t|
      t.integer :num
      t.boolean :blocked, default: false
    end
  end
end
