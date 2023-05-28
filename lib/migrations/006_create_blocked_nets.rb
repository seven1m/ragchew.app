class CreateBlockedNets < ActiveRecord::Migration[7.0]
  def change
    create_table :blocked_nets do |t|
      t.string :name, null: false
      t.string :reason
      t.timestamps

      t.index :name, unique: true
    end
  end
end
