class AddLoggerDetailsToNets < ActiveRecord::Migration[7.0]
  def change
    change_table :nets do |t|
      t.integer :logger_user_id
      t.string :logger_password, limit: 100
    end
  end
end
