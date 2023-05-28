module Tables
  class User < ActiveRecord::Base
    validates :call_sign, presence: true

    belongs_to :monitoring_net
    has_many :favorites, dependent: :delete_all

    scope :is_monitoring, -> { where.not(monitoring_net_id: nil) }
  end
end
