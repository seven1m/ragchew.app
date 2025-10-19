require_relative '../net_like'

module Tables
  class ClosedNet < ActiveRecord::Base
    include NetLike

    belongs_to :club, optional: true

    validates :name, presence: true

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
          'club_id',
          'created_by_ragchew',
        )
      )
      closed_net.ended_at = Time.now
      closed_net.checkin_count = net.checkins.count
      closed_net.message_count = net.messages.count
      closed_net.message_reaction_count = net.message_reactions.count
      closed_net.monitor_count = net.monitors.count
      closed_net
    end
  end
end
