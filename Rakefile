require 'bundler/setup'
require 'active_record'
require './lib/migrations/001_create_tables'
require './lib/migrations/002_create_users'

db_config = YAML.safe_load(File.read('config/database.yaml')) 
env = ENV['RACK_ENV'] || 'development'
ActiveRecord::Base.establish_connection(db_config[env])

namespace :db do
  task :migrate do
    # TODO: figure this out later :-)
    CreateTables.new.up
    CreateUsers.new.up
  end

  namespace :migrate do
    task :redo do
      CreateUsers.new.down
      CreateTables.new.down
      CreateTables.new.up
      CreateUsers.new.up
    end
  end
end
