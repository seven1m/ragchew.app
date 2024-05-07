module Tables
  class User < ActiveRecord::Base
    validates :call_sign, presence: true

    belongs_to :monitoring_net, class_name: 'Net'
    has_many :favorites, dependent: :delete_all
    has_one :logging_net, class_name: 'Net', foreign_key: 'logger_user_id'
    has_many :club_admins, dependent: :delete_all

    scope :is_monitoring, -> { where.not(monitoring_net_id: nil) }

    def name
      [first_name, last_name].compact.join(' ')
    end

    def admin?
      flags & 1 == 1
    end

    def admin=(value)
      self.flags = (value ? 1 : 0) + (flags & 2)
    end

    def net_logger?
      flags & 2 == 2
    end

    def net_logger=(value)
      self.flags = (flags & 1) + (value ? 2 : 0)
    end
  end
end
