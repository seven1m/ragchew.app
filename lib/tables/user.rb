module Tables
  class User < ActiveRecord::Base
    validates :call_sign, presence: true

    belongs_to :monitoring_net, class_name: 'Net'
    has_many :favorites, dependent: :delete_all
    belongs_to :logging_net, class_name: 'Net', optional: true
    has_many :club_members, dependent: :delete_all
    has_many :clubs, through: :club_members

    scope :is_monitoring, -> { where.not(monitoring_net_id: nil) }

    enum :time_format, {
      local_24: 0,
      local_12: 1,
      utc_24: 2,
    }

    validates :theme, inclusion: { in: %w[system light dark] }

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

    def can_log_for_club?(club)
      return false unless club
      return false unless net_logger?

      club_members.where(club_id: club.id).exists?
    end
  end
end
