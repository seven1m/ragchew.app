module Tables
  class Station < ActiveRecord::Base
    EXPIRATION_IN_SECONDS = 24 * 60 * 60

    def extend_expiration
      self.expires_at = Time.now + EXPIRATION_IN_SECONDS
      self
    end

    def expired?
      !expires_at || expires_at < Time.now
    end
  end
end
