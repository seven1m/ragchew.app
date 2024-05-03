module Tables
  class Station < ActiveRecord::Base
    EXPIRATION_IN_SECONDS = 24 * 60 * 60

    scope :expired, -> { where('expires_at is null or expires_at < ?', Time.now) }
    scope :not_favorited, -> { joins('left join favorites on favorites.call_sign = stations.call_sign').where('favorites.id is null') }

    def extend_expiration
      self.expires_at = Time.now + EXPIRATION_IN_SECONDS
      self
    end

    def expired?
      !expires_at || expires_at < Time.now
    end
  end
end
