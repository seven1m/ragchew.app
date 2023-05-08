module Tables
  class User < ActiveRecord::Base
    validates :call_sign, presence: true
  end
end
