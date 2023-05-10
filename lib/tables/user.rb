module Tables
  class User < ActiveRecord::Base
    validates :call_sign, presence: true

    belongs_to :monitoring_net, class_name: 'Tables::Net'
  end
end
