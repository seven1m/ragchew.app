module Tables
  class Favorite < ActiveRecord::Base
    validates :call_sign, presence: true
    belongs_to :user, class_name: 'Tables::User'
  end
end
