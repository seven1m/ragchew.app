class AddMessageReactionCountToClosedNets < ActiveRecord::Migration[7.2]
  def change
    add_column :closed_nets, :message_reaction_count, :integer, null: false, default: 0
  end
end
