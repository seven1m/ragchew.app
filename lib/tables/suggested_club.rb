module Tables
  class SuggestedClub < ActiveRecord::Base
    validates :name, presence: true
    validates :suggested_by, presence: true
  end
end
