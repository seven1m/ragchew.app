module Tables
  class User < ActiveRecord::Base
    validates :call_sign, presence: true
    validates :hashed_password, presence: true
  end
end
