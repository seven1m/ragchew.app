module Tables
  class FavoriteNet < ActiveRecord::Base
    validates :net_name, presence: true
    belongs_to :user, class_name: 'Tables::User'
  end
end
