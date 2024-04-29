module Tables
  class User < ActiveRecord::Base
    validates :call_sign, presence: true

    belongs_to :monitoring_net, class_name: 'Net'
    has_many :favorites, dependent: :delete_all

    scope :is_monitoring, -> { where.not(monitoring_net_id: nil) }

    include FlagShihTzu

    has_flags 1 => :admin,
              2 => :net_logger

    # TEMPORARY: Remove this once I set myself as an admin.
    alias admin_flag? admin?
    def admin?
      ENV.fetch('ADMIN_CALL_SIGNS').split(',').include?(call_sign) || admin_flag?
    end
  end
end
