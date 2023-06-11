require_relative './boot'

Dir['./lib/migrations/*.rb'].to_a.each do |file|
  require file
end

template = Erubis::Eruby.new(File.read('config/database.yaml'))
db_config = YAML.safe_load(template.result) 
env = ENV['RACK_ENV'] || 'development'
ActiveRecord::Base.establish_connection(db_config[env])

namespace :db do
  task :migrate do
    context = ActiveRecord::MigrationContext.new(
      File.expand_path('lib/migrations', __dir__),
      ActiveRecord::SchemaMigration
    )
    version = ENV['TO_VERSION']&.to_i
    context.migrate(version)
  end
end

task :console do
  require 'irb'
  binding.irb
end

task :runner do
  eval(ENV.fetch('CODE'))
end

MAX_IDLE_MONITORING_IN_SECONDS = 5 * 60 # 5 minutes

# Runs every 5 minutes
task :cleanup do
  # users stop monitoring if they have not refreshed the page in a while
  scope = Tables::User
    .is_monitoring
    .where('monitoring_net_last_refreshed_at < ?', Time.now - MAX_IDLE_MONITORING_IN_SECONDS)
  count = scope.count
  scope.find_each do |user|
    if (net = user.monitoring_net)
      NetInfo.new(id: net.id).stop_monitoring!(user:)
    end
    user.update!(
      monitoring_net: nil,
      monitoring_net_last_refreshed_at: nil,
    )
  end
  puts "#{count} user(s) stopped monitoring"
end

# Runs every 10 minutes
task :populate do
  ActiveRecord::Base.logger = Logger.new($stdout)
  nets = NetList.new.list
  nets.each do |net|
    begin
      NetInfo.new(id: net.id).update!
    rescue NetInfo::NotFoundError
      # it closed while we were looping
    end
    sleep 5
  end
end

# Runs nightly
task :update_club_list do
  ActiveRecord::Base.logger = Logger.new($stdout)
  UpdateClubList.new.call
  Tables::Club.find_each do |club|
    AssociateClubWithNets.new(
      club,
      only_blank: true,
    ).call
  end
end

# Runs every 5 minutes
task :associate_clubs_with_new_nets do
  ActiveRecord::Base.logger = Logger.new($stdout)
  Tables::Club.find_each do |club|
    AssociateClubWithNets.new(
      club,
      only_blank: true,
      created_seconds_ago: 15 * 60,
    ).call
  end
end

# Only run this manually to associate clubs with existing open and closed nets.
task :associate_clubs_with_all_nets do
  ActiveRecord::Base.logger = Logger.new($stdout)
  Tables::Club.find_each do |club|
    AssociateClubWithNets.new(club, only_blank: true).call
  end
end
