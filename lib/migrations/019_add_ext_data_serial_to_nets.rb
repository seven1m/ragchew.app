class AddExtDataSerialToNets < ActiveRecord::Migration[7.0]
  def change
    change_table :nets do |t|
      t.integer :ext_data_serial, default: 0
    end
  end
end
