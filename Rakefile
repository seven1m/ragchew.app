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

    last_hour = 1.hour.ago.beginning_of_hour
    range = last_hour..Time.zone.now

    build_stats(range, 'hour', last_hour)
  end

  task :daily do
    Time.zone = 'America/Chicago'

    last_day = 1.day.ago.beginning_of_day
    range = last_day..Time.zone.now

    build_stats(range, 'day', last_day)
  end

  task :weekly do
    Time.zone = 'America/Chicago'

    last_week = 7.days.ago.beginning_of_week
    range = last_week..Time.zone.now

    build_stats(range, 'week', last_week)
  end

  task :monthly do
    Time.zone = 'America/Chicago'

    last_month = 15.days.ago.beginning_of_month
    range = last_month..Time.zone.now

    build_stats(range, 'month', last_month)
  end

  task :clear do
    Tables::Stat.delete_all
  end

  task :fix_daily do
    Time.zone = 'America/Chicago'

    Tables::Stat.where("name like '%per_day'").find_each do |stat|
      stat.period = stat.period.beginning_of_hour
      stat.save!
    end
  end
end
