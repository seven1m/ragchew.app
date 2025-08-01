class AddThemeToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :theme, :string, default: 'system', null: false
  end
end
