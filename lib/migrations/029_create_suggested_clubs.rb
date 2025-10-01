class CreateSuggestedClubs < ActiveRecord::Migration[7.0]
  def change
    create_table :suggested_clubs do |t|
      t.string :name, null: false
      t.string :full_name
      t.string :website
      t.text :description
      t.text :nets
      t.string :suggested_by
      t.timestamps
    end
  end
end
