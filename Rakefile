require_relative './boot'

require_relative './lib/migrations/001_create_users'
require_relative './lib/migrations/002_create_tables'
require_relative './lib/migrations/003_add_monitoring_net_id_to_users'

template = Erubis::Eruby.new(File.read('config/database.yaml'))
db_config = YAML.safe_load(template.result) 
env = ENV['RACK_ENV'] || 'development'
ActiveRecord::Base.establish_connection(db_config[env])

namespace :db do
  task :migrate do
    CreateUsers.new.up
    CreateTables.new.up
    AddMonitoringNetIdToUsers.new.change
  end

  namespace :migrate do
    task :redo do
      CreateTables.new.down
      CreateTables.new.up
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

  # old checkins get cleaned up
  # (we keep the most recent 100 around so the homepage has something to show)
  total = Tables::Checkin.where(net_id: nil).count
  count_to_delete = [0, total - 100].max
  if count_to_delete > 0
    Tables::Checkin.where(net_id: nil).order(:updated_at).limit(count_to_delete).delete_all
  end
  puts "#{count_to_delete} checkin(s) deleted"
end

# Runs twice daily
task :populate do
  ActiveRecord::Base.logger = Logger.new($stdout)
  nets = NetList.new.list
  if (random_net = nets.sample)
    NetInfo.new(id: random_net.id).net
  end
end
