class RenameNicknameToPreferredNameOnCheckins < ActiveRecord::Migration[7.0]
  def change
    change_table :checkins do |t|
      t.rename :nickname, :preferred_name
    end
  end
end
