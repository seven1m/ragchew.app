class AssociateClubWithNets
  def initialize(club, only_blank: true, created_seconds_ago: nil)
    @club = club
    @only_blank = only_blank
    @created_seconds_ago = created_seconds_ago
  end

  def call
    patterns = @club.all_patterns

    net_scope = Tables::Net.all
    limit_scope(net_scope)
    net_scope.matching_patterns(patterns).each do |net|
      net.update!(club: @club)
    end

    closed_net_scope = Tables::ClosedNet.all
    limit_scope(closed_net_scope)
    closed_net_scope.matching_patterns(patterns).each do |closed_net|
      closed_net.update!(club: @club)
    end
  end

  private

  def limit_scope(scope)
    scope.where!(club_id: nil) if @only_blank
    scope.where!('created_at > ?', Time.now - @created_seconds_ago) if @created_seconds_ago
  end
end
