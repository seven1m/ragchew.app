class AddCreatedByRagchewToClosedNets < ActiveRecord::Migration[7.2]
  def change
    add_column :closed_nets, :created_by_ragchew, :boolean, default: false
  end
end
