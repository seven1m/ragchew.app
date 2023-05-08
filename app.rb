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
require_relative './lib/qrz'

enable :sessions

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
  @user = session[:user_id] && Tables::User.find(session[:user_id])
  service = NetList.new
  @nets = service.list
  @last_updated_at = @nets.sort_by { |n| n.updated_at }.last.updated_at
  erb :index
end

get '/net/:name' do
  @user = session[:user_id] && Tables::User.find(session[:user_id])
  unless @user
    redirect "/login?net=#{params[:name]}"
    return
  end

  service = NetInfo.new(CGI.unescape(params[:name]))
  @net = service.info
  @last_updated_at = @net.updated_at
  erb :net
rescue NetInfo::NotFoundError => e
  @message = e.message
  erb :missing, status: 404
end

get '/login' do
  erb :login
end

post '/login' do
  qrz = Qrz.login(
    username: params[:call_sign],
    password: params[:password],
  )
  result = qrz.lookup(params[:call_sign])

  @user = Tables::User.find_or_initialize_by(call_sign: result[:call_sign])
  @user.update!(result)

  session[:user_id] = @user.id

  redirect params[:net] ? "/net/#{params[:net]}" : '/'
rescue Qrz::Error => e
  @error = e.message
  erb :login
end

get '/logout' do
  session.delete(:user_id)
  redirect '/'
end
