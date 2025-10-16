module Tables
  class Message < ActiveRecord::Base
    belongs_to :net
    has_many :message_reactions, dependent: :delete_all

    def as_json(options = {})
      if options[:include_reactions]
        super.merge(
          reactions: message_reactions
        )
      else
        super
      end
    end
  end
end
