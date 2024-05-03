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
MAX_IDLE_NET_IN_SECONDS = 30 * 60 # 30 minutes

# Runs every 5 minutes
task :cleanup do
  # users stop monitoring if they have not refreshed the page in a while
  scope = Tables::User
    .is_monitoring
    .where('monitoring_net_last_refreshed_at < ?', Time.now - MAX_IDLE_MONITORING_IN_SECONDS)
  count = 0
  scope.find_each do |user|
    next if user.logging_net == user.monitoring_net

    if (net = user.monitoring_net)
      NetInfo.new(id: net.id).stop_monitoring!(user:)
    end
    user.update!(
      monitoring_net: nil,
      monitoring_net_last_refreshed_at: nil,
    )
    count += 1
  end
  puts "#{count} user(s) stopped monitoring"

  # nets close if they have no updates in a while
  count = 0
  Tables::Net.where.not(logger_user_id: nil).find_each do |net|
    if net.checkins.maximum(:updated_at) < Time.now - MAX_IDLE_NET_IN_SECONDS
      logger = NetLogger.new(NetInfo.new(id: net.id), user: net.logger_user)
      logger.close_net!
      count += 1
    end
  end
  puts "#{count} net(s) closed"

  # stations are removed if they are expired and are not favorited by any user
  scope = Tables::Station.expired.not_favorited
  count = scope.count
  scope.delete_all
  puts "#{count} expired station(s) deleted"
end

# Runs every 10 minutes
task :populate do
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
  UpdateClubList.new.call
end

# Deploy to Dokku and notify Honeybadger
task :deploy do
  sh 'git push dokku master'

  require 'honeybadger'
  Honeybadger.track_deployment(
    environment: 'production',
    revision: `git rev-parse HEAD`.strip,
    local_username: `whoami`.strip,
    repository: "git@github.com:seven1m/ragchew.app"
  )
end
