require_relative './boot'

Dir['./lib/migrations/*.rb'].to_a.each do |file|
  require file
end

template = eval(Erubi::Engine.new(File.read('config/database.yaml')).src)
db_config = YAML.safe_load(template)
env = ENV['RACK_ENV'] || 'development'
ActiveRecord::Base.establish_connection(db_config[env])

namespace :db do
  task :migrate do
    context = ActiveRecord::MigrationContext.new(
      File.expand_path('lib/migrations', __dir__)
    )
    version = ENV['TO_VERSION']&.to_i
    context.migrate(version)
  end

  namespace :migrate do
    task :down do
      context = ActiveRecord::MigrationContext.new(
        File.expand_path('lib/migrations', __dir__),
        ActiveRecord::SchemaMigration
      )
      raise 'not at latest' if context.needs_migration?
      latest = context.current_version
      context.migrate(latest - 1)
    end

    task :redo do
      context = ActiveRecord::MigrationContext.new(
        File.expand_path('lib/migrations', __dir__),
        ActiveRecord::SchemaMigration
      )
      raise 'not at latest' if context.needs_migration?
      latest = context.current_version
      context.migrate(latest - 1)
      context.migrate(latest)
    end
  end
end

task :console do
  require 'irb'
  binding.irb
end

task :db do
  require 'uri'

  db_url = ENV['DATABASE_URL']
  raise 'DATABASE_URL not set' unless db_url

  uri = URI.parse(db_url)

  cmd = ['mysql']
  cmd << "-h#{uri.host}" if uri.host
  cmd << "-P#{uri.port}" if uri.port
  cmd << "-u#{uri.user}" if uri.user
  cmd << "-p#{uri.password}" if uri.password
  cmd << uri.path[1..-1] if uri.path && uri.path.length > 1

  exec(*cmd)
end

task :runner do
  eval(ENV.fetch('CODE'))
end

MAX_IDLE_MONITORING = 5.minutes
MAX_IDLE_NET = 30.minutes

# Runs every 5 minutes
task :cleanup do
  # users stop monitoring if they have not refreshed the page in a while
  scope = Tables::User
    .is_monitoring
    .where('monitoring_net_last_refreshed_at < ?', MAX_IDLE_MONITORING.ago)
  count = 0
  scope.find_each do |user|
    next if user.logging_net == user.monitoring_net

    if (net = user.monitoring_net)
      begin
        NetInfo.new(id: net.id).stop_monitoring!(user:)
      rescue NetInfo::NotFoundError
        # no problem
      end
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
  Tables::Net.where(created_by_ragchew: true).find_each do |net|
    # If the logger clicks 'stop logging' then we don't have a user to close the net with.
    next unless (user = net.logging_users.first)

    last_activity = [net.checkins.maximum(:updated_at), net.messages.maximum(:created_at), net.created_at].compact.max
    if last_activity < MAX_IDLE_NET.ago
      logger = NetLogger.new(NetInfo.new(id: net.id), user:)
      logger.close_net! rescue nil
      count += 1
    end
  end
  puts "#{count} net(s) closed"
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

def build_stats(range, period_name, period)
  new_users = Tables::User.where(created_at: range).count
  Tables::Stat.find_or_initialize_by(name: "new_users_per_#{period_name}", period:).update!(value: new_users)

  active_users = Tables::User.where(last_signed_in_at: range).count
  Tables::Stat.find_or_initialize_by(name: "active_users_per_#{period_name}", period:).update!(value: active_users)
end

task :stats do
  Time.zone = 'America/Chicago'
  now = Time.zone.now

  if now.hour == 0 && now.wday == 1
    week_start = now.beginning_of_week - 1.week
  else
    week_start = now.beginning_of_week
  end

  range = week_start..(week_start + 1.week)
  puts "Building weekly stats for #{range.begin.strftime('%Y-%m-%d')} - #{range.end.strftime('%Y-%m-%d')}"
  build_stats(range, 'week', week_start)
end
