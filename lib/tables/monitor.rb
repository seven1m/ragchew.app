module Tables
  class Monitor < ActiveRecord::Base
    belongs_to :net

    scope :blocked, -> { where(blocked: true) }
  end
end
