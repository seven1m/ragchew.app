module Tables
  class User < ActiveRecord::Base
    validates :call_sign, presence: true

    belongs_to :monitoring_net, class_name: 'Tables::Net'
    has_many :favorites, class_name: 'Tables::Favorite'

    scope :is_monitoring, -> { where.not(monitoring_net_id: nil) }
  end
end
