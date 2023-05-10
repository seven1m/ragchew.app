class AddMonitoringNetIdToUsers < ActiveRecord::Migration[7.0]
  def change
    change_table :users do |t|
      t.references :monitoring_net
      t.datetime :monitoring_net_last_refreshed_at
    end
  end
end
