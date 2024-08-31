class AddTimeFormatToUsers < ActiveRecord::Migration[7.0]
  def change
    change_table :users do |t|
      t.integer :time_format, default: 0
    end
  end
end
