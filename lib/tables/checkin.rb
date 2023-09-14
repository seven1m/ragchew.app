module Tables
  class Checkin < ActiveRecord::Base
    belongs_to :net

    def checked_out?
      status.include?('(c/o)')
    end
  end
end
