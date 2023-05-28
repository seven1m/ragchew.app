module Tables
  class BlockedNet < ActiveRecord::Base
    validates :name, presence: true
  end
end
