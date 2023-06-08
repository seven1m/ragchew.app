class AddOverridesToClubs < ActiveRecord::Migration[7.0]
  def change
    change_table :clubs do |t|
      t.boolean :override_about_url
      t.boolean :override_logo_url
    end
  end
end
