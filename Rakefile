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

MINUTE = 60
MAX_IDLE_MONITORING_IN_SECONDS = 5 * MINUTE
MAX_IDLE_NET_IN_SECONDS = 45 * MINUTE

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
  Tables::Net.where(created_by_ragchew: true).find_each do |net|
    if net.checkins.maximum(:updated_at) < Time.now - MAX_IDLE_NET_IN_SECONDS
      next unless (user = net.logging_users.first)

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

namespace :stats do
  def build_stats(range, period_name,  period)
    nets = Tables::Net.where(created_at: range).count
    closed_nets = Tables::ClosedNet.where(created_at: range).count
    Tables::Stat.find_or_initialize_by(name: "nets_per_#{period_name}", period:).update!(value: nets + closed_nets)

    new_users = Tables::User.where(created_at: range).count
    Tables::Stat.find_or_initialize_by(name: "new_users_per_#{period_name}", period:).update!(value: new_users)

    active_users = Tables::User.where(last_signed_in_at: range).count
    Tables::Stat.find_or_initialize_by(name: "active_users_per_#{period_name}", period:).update!(value: active_users)
  end

  task :hourly do
    Time.zone = 'America/Chicago'

    last_hour = (Time.zone.now - 1.hour).beginning_of_hour
    range = last_hour..last_hour.end_of_hour

    build_stats(range, 'hour', last_hour)
  end

  task :daily do
    Time.zone = 'America/Chicago'

    last_day = (Time.zone.now - 1.day).beginning_of_day
    range = last_day..last_day.end_of_day

    build_stats(range, 'day', last_day)
  end

  task :weekly do
    Time.zone = 'America/Chicago'

    last_week = (Time.zone.now - 7.days).beginning_of_week
    range = last_week..last_week.end_of_week

    build_stats(range, 'week', last_week)
  end

  task :monthly do
    Time.zone = 'America/Chicago'

    last_month = (Time.zone.now - 15.days).beginning_of_month
    range = last_month..last_month.end_of_month

    build_stats(range, 'month', last_month)
  end
end
