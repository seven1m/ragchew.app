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

    last_activity = [net.checkins.maximum(:updated_at), net.messages.maximum(:created_at)].compact.max
    if last_activity < MAX_IDLE_NET.ago
      logger = NetLogger.new(NetInfo.new(id: net.id), user:)
      logger.close_net! rescue nil
      count += 1
    end
  end
  puts "#{count} net(s) closed"

  # stations are removed if they are expired (and not connected to something else)
  scope = Tables::Station.expired.not_favorited.have_no_user
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

def build_stats(range, period_name, period)
  nets = Tables::Net.where(created_at: range).count
  closed_nets = Tables::ClosedNet.where(created_at: range).count
  Tables::Stat.find_or_initialize_by(name: "nets_per_#{period_name}", period:).update!(value: nets + closed_nets)

  new_users = Tables::User.where(created_at: range).count
  Tables::Stat.find_or_initialize_by(name: "new_users_per_#{period_name}", period:).update!(value: new_users)

  active_users = Tables::User.where(last_signed_in_at: range).count
  Tables::Stat.find_or_initialize_by(name: "active_users_per_#{period_name}", period:).update!(value: active_users)
end

task :stats do
  Time.zone = 'America/Chicago'
  now = Time.zone.now

  # Back up to previous hour since cron runs at the beginning of each hour
  previous_hour = now.beginning_of_hour - 1.hour
  range = previous_hour..(previous_hour + 1.hour)
  puts "Building hourly stats for #{previous_hour.strftime('%Y-%m-%d %H:00')} - #{range.end.strftime('%Y-%m-%d %H:00')}"
  build_stats(range, 'hour', previous_hour)

  # Only run daily/weekly/monthly stats at specific times to avoid duplicates
  if now.hour == 0  # Run daily stats at midnight
    previous_day = now.beginning_of_day - 1.day
    range = previous_day..(previous_day + 1.day)
    puts "Building daily stats for #{previous_day.strftime('%Y-%m-%d')} - #{range.end.strftime('%Y-%m-%d')}"
    build_stats(range, 'day', previous_day)
  end

  if now.hour == 0 && now.wday == 1  # Run weekly stats at midnight on Monday
    previous_week = now.beginning_of_week - 1.week
    range = previous_week..(previous_week + 1.week)
    puts "Building weekly stats for #{previous_week.strftime('%Y-%m-%d')} - #{range.end.strftime('%Y-%m-%d')}"
    build_stats(range, 'week', previous_week)
  end

  if now.hour == 0 && now.day == 1  # Run monthly stats at midnight on the 1st
    previous_month = now.beginning_of_month - 1.month
    range = previous_month..(previous_month + 1.month)
    puts "Building monthly stats for #{previous_month.strftime('%Y-%m-%d')} - #{range.end.strftime('%Y-%m-%d')}"
    build_stats(range, 'month', previous_month)
  end
end
