module Tables
  class ClosedNet < ActiveRecord::Base
    validates :name, presence: true

    def show_circle?
      center_latitude && center_longitude && center_radius
    end

    def self.from_net(net)
      closed_net = ClosedNet.new(
        net.attributes.slice(
          'name',
          'frequency',
          'mode',
          'net_control',
          'net_logger',
          'band',
          'started_at',
          'subscribers',
          'host',
          'center_latitude',
          'center_longitude',
          'center_radius',
        )
      )
      closed_net.ended_at = Time.now
      closed_net.checkin_count = net.checkins.count
      closed_net.message_count = net.messages.count
      closed_net.monitor_count = net.monitors.count
      closed_net
    end
  end
end
