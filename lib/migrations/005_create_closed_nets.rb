class CreateClosedNets < ActiveRecord::Migration[7.0]
  def change
    create_table :closed_nets do |t|
      t.string :name, null: false
      t.string :frequency
      t.string :mode
      t.string :net_control
      t.string :net_logger
      t.string :band
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.integer :subscribers
      t.string :host, null: false
      t.float :center_latitude
      t.float :center_longitude
      t.integer :center_radius
      t.integer :checkin_count, null: false
      t.integer :message_count, null: false
      t.integer :monitor_count, null: false
      t.timestamps

      t.index %i[name started_at]
    end
  end
end
