module Tables
  class ClubStation < ActiveRecord::Base
    belongs_to :club
    validates :call_sign, presence: true
  end
end
