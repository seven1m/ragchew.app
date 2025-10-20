module Tables
  class ClubStation < ActiveRecord::Base
    belongs_to :club
    belongs_to :station, foreign_key: :call_sign, primary_key: :call_sign
    validates :call_sign, presence: true
  end
end
