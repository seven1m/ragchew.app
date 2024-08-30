class AddLoggingNetToUsers < ActiveRecord::Migration[7.0]
  def change
    change_table :users do |t|
      t.integer :logging_net_id
      t.string :logging_password, limit: 100
    end

    change_table :nets do |t|
      t.boolean :created_by_ragchew, default: false
    end

    remove_column :nets, :logger_user_id, :integer
    remove_column :nets, :logger_password, :integer
  end
end
