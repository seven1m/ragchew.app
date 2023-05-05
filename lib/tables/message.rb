module Tables
  class Message < ActiveRecord::Base
    belongs_to :net
  end
end
