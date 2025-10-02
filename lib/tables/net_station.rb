module Tables
  class NetStation < ActiveRecord::Base
    validates :net_name, presence: true
    validates :call_sign, presence: true
  end
end
