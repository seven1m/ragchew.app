module Tables
  class ClosedNet < ActiveRecord::Base
    validates :name, presence: true

    def show_circle?
      center_latitude && center_longitude && center_radius
    end
  end
end
