module Tables
  class Net < ActiveRecord::Base
    belongs_to :server
    has_many :checkins, dependent: :nullify # these get cleaned up by `rake cleanup`
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

    def show_circle?
      center_latitude && center_longitude && center_radius
    end
  end
end
