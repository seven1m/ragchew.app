class AddLoggingNetToUsers < ActiveRecord::Migration[7.0]
  def change
    change_table :users do |t|
      t.integer :logging_net_id
    end

    remove_column :nets, :logger_user_id, :integer
  end
end
