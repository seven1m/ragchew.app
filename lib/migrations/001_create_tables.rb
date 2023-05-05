class CreateTables < ActiveRecord::Migration[7.0]
  def up
    create_table :nets do |t|
      t.string :name
      t.string :alt_name
      t.string :frequency
      t.string :mode
      t.string :net_control
      t.string :net_logger
      t.string :band
      t.datetime :started_at
      t.boolean :im_enabled
      t.integer :update_interval
      t.integer :subscribers
      t.string :host
      t.datetime :partially_updated_at
      t.datetime :fully_updated_at
      t.timestamps

      t.index :name
    end

    create_table :checkins do |t|
      t.references :net
      t.integer :num
      t.string :call_sign
      t.string :name
      t.string :nickname
      t.string :remarks
      t.string :qsl_info
      t.datetime :checked_in_at
      t.string :grid_square
      t.string :street
      t.string :city
      t.string :state
      t.string :zip
      t.string :county
      t.string :country
      t.string :status
      t.string :dscc
      t.boolean :currently_operating, default: false, null: false
      t.timestamps
    end

    create_table :monitors do |t|
      t.references :net
      t.string :call_sign
      t.string :version
      t.string :status
      t.string :ip_address
      t.timestamps
    end

    create_table :messages do |t|
      t.references :net
      t.integer :log_id
      t.string :call_sign
      t.text :message
      t.datetime :sent_at
      t.string :ip_address
      t.timestamps
    end
  end

  def down
    drop_table :nets
    drop_table :checkins
    drop_table :monitors
    drop_table :messages
  end
end
