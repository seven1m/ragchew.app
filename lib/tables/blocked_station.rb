module Tables
  class BlockedStation < ActiveRecord::Base
    belongs_to :blocker, polymorphic: true
    validates :call_sign, presence: true
  end
end
