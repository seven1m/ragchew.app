require 'bundler/setup'

require 'active_record'
require 'erubis'
require 'dotenv/load'
require 'dotiw'
require 'cgi'
require 'erb'
require 'honeybadger'
require 'json'
require 'net/http'
require 'nokogiri'
require 'pusher'
require 'redcarpet'
require 'time'
require 'uri'
require 'yaml'
require 'with_advisory_lock'

template = Erubis::Eruby.new(File.read('config/database.yaml'))
db_config = YAML.safe_load(template.result)
env = ENV['RACK_ENV'] == 'production' ? :production : :development
ActiveRecord::Base.establish_connection(db_config[env.to_s])
ActiveRecord::Base.logger = Logger.new($stderr) if ENV['DEBUG_SQL']

require_relative './lib/associate_club_with_nets'
require_relative './lib/associate_net_with_club'
require_relative './lib/extensions'
require_relative './lib/fetcher'
require_relative './lib/grid_square'
require_relative './lib/net_info'
require_relative './lib/net_like'
require_relative './lib/net_logger'
require_relative './lib/net_list'
require_relative './lib/qrz'
require_relative './lib/qrz_auto_session'
require_relative './lib/station_updater'
require_relative './lib/tables'
require_relative './lib/update_club_list'
