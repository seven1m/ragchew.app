require 'bundler/setup'
require 'active_record'
require 'erubis'
require './lib/migrations/001_create_users'
require './lib/migrations/002_create_tables'

template = Erubis::Eruby.new(File.read('config/database.yaml'))
db_config = YAML.safe_load(template.result) 
env = ENV['RACK_ENV'] || 'development'
ActiveRecord::Base.establish_connection(db_config[env])

namespace :db do
  task :migrate do
    CreateUsers.new.up
    CreateTables.new.up
  end

  namespace :migrate do
    task :redo do
      CreateTables.new.down
      CreateTables.new.up
    end
  end
end
