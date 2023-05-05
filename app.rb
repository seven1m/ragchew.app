require 'bundler/setup'

require 'active_record'
require 'dotiw'
require 'cgi'
require 'erb'
require 'net/http'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'scrypt'
require 'time'
require 'uri'
require 'yaml'

require_relative './lib/net_info'
require_relative './lib/net_list'

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
  @user = session[:user] && Tables::User.find(session[:user])
  service = NetList.new
  @nets = service.list
  @last_updated_at = @nets.sort_by { |n| n.updated_at }.last.updated_at
  erb :index
end

get '/net/:name' do
  @user = session[:user] && Tables::User.find(session[:user])
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

get '/register' do
  erb :register
end

post '/register' do
  if Tables::User.find_by(call_sign: params[:call_sign])
    erb "Already registered", status: 401
    return
  end

  if params[:password] != params[:password_confirmation]
    erb "Passwords do not match", status: 401
    return
  end

  if params[:password].size < 8
    erb "Passwords must be 8 or more characters", status: 401
    return
  end

  @user = Tables::User.create!(
    call_sign: params[:call_sign],
    hashed_password: SCrypt::Password.create(params[:password])
  )
  session[:user] = @user.id
  redirect '/'
end

get '/login' do
  erb :login
end

post '/login' do
  @user = Tables::User.find_by(call_sign: params[:call_sign])
  unless @user
    erb "Not found", status: 404
    return
  end

  if SCrypt::Password.new(@user.hashed_password) == params[:password]
    session[:user] = @user.id
  else
    erb "Password incorrect", status: 401
  end

  redirect params[:net] ? "/net/#{params[:net]}" : '/'
end

get '/logout' do
  session.delete(:user)
  redirect '/'
end
