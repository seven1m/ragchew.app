module Tables
  class Station < ActiveRecord::Base
    EXPIRATION_IN_SECONDS = 24 * 60 * 60

    before_save :set_expires_at

    def set_expires_at
      self.expires_at = Time.now + EXPIRATION_IN_SECONDS
    end

    def expired?
      expires_at && expires_at < Time.now
    end
  end
end
