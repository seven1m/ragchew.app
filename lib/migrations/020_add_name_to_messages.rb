class AddNameToMessages < ActiveRecord::Migration[7.0]
  def change
    change_table :messages do |t|
      t.string :name
    end
  end
end
