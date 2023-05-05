require 'bundler/setup'

require 'active_record'
require 'dotiw'
require 'cgi'
require 'erb'
require 'net/http'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'time'
require 'uri'
require 'yaml'

require_relative './lib/net_info'
require_relative './lib/net_list'

if development?
  Dir['./lib/**/*.rb'].each do |path|
    also_reload(path)
  end
end

include DOTIW::Methods

ENV['TZ'] = 'UTC'

db_config = YAML.safe_load(File.read('config/database.yaml')) 
env = development? ? :development : :production
ActiveRecord::Base.establish_connection(db_config[env.to_s])
ActiveRecord::Base.logger = Logger.new($stderr) if development?

get '/' do
  service = NetList.new
  @nets = service.list
  @last_updated_at = @nets.sort_by { |n| n.updated_at }.last.updated_at
  erb :index
end

get '/net/:name' do
  service = NetInfo.new(CGI.unescape(params[:name]))
  @net = service.info
  @last_updated_at = @net.updated_at
  erb :net
rescue NetInfo::NotFoundError => e
  @message = e.message
  erb :missing, status: 404
end
