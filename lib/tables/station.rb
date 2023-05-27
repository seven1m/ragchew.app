module Tables
  class Station < ActiveRecord::Base
    EXPIRATION_IN_SECONDS = 24 * 60 * 60

    def expire_image
      self.image_expires_at = Time.now + EXPIRATION_IN_SECONDS
      self
    end

    def image_expired?
      image_expires_at && image_expires_at < Time.now
    end
  end
end
