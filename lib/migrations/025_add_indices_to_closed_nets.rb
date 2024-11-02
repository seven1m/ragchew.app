class AddIndicesToClosedNets < ActiveRecord::Migration[7.0]
  def change
    change_table :closed_nets do |t|
      t.index %i[started_at name frequency]
    end
  end
end
