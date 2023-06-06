class AddAdditionalNetPatternsToClubs < ActiveRecord::Migration[7.0]
  def change
    change_table :clubs do |t|
      t.text :additional_net_patterns
    end
  end
end
