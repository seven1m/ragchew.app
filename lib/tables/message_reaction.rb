module Tables
  class MessageReaction < ActiveRecord::Base
    belongs_to :message
  end
end
