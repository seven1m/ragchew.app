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

task :cleanup do
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
