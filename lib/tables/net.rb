require_relative '../net_like'

module Tables
  class Net < ActiveRecord::Base
    include NetLike

    belongs_to :server
    belongs_to :club, optional: true
    has_many :checkins, dependent: :delete_all
    has_many :monitors, dependent: :delete_all
    has_many :messages, dependent: :delete_all

    def self.all_by_name
      all.each_with_object({}) do |net, hash|
        hash[net.name] = net
      end
    end

    def update_interval_in_seconds
      if update_interval
        update_interval / 1000
      else
        20
      end
    end
  end
end
