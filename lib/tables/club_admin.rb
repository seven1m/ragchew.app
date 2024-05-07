module Tables
  class ClubAdmin < ActiveRecord::Base
    belongs_to :club
    belongs_to :user

    def editor?
      flags & 1 == 1
    end

    def editor=(value)
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
