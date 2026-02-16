module Tables
  class ApiToken < ActiveRecord::Base
    belongs_to :user

    validates :token, presence: true, uniqueness: true

    def self.generate_for(user)
      create!(
        user: user,
        token: SecureRandom.hex(32),
      )
    end

    def touch_last_used!
      update!(last_used_at: Time.now)
    end
  end
end
