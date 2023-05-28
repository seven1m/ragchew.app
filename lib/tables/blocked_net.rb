module Tables
  class BlockedNet < ActiveRecord::Base
    validates :name, presence: true

    def self.blocked?(name, names: BlockedNet.pluck(:name))
      names.any? do |blocked_name|
        if blocked_name.start_with?('/') && blocked_name.end_with?('/')
          Regexp.new(blocked_name[1...-1], 'i') =~ name
        else
          blocked_name == name
        end
      end
    end
  end
end
