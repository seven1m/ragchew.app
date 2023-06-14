class AssociateNetWithClub
  def initialize(net, force_update: false)
    @net = net
    @force_update = force_update
  end

  def self.clubs_cache
    @clubs ||= Tables::Club.all.to_a
  end

  def self.clear_clubs_cache
    @clubs = nil
  end

  def call
    @net.club = nil if @force_update

    @net.club ||= self.class.clubs_cache.detect do |club|
      club.matches_net?(@net)
    end
  end
end
