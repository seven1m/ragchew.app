module Tables
  class Net < ActiveRecord::Base
    has_many :checkins, dependent: :delete_all
    has_many :monitors, dependent: :delete_all
    has_many :messages, dependent: :delete_all

    def self.all_by_name
      all.each_with_object({}) do |net, hash|
        hash[net.name] = net
      end
    end
  end
end
