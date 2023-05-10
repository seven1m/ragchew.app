require 'bundler/setup'

require 'active_record'
require 'erubis'
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
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }

if development?
  Dir['./lib/**/*.rb'].each do |path|
    also_reload(path)
  end
end

helpers do
  def format_time(ts)
    return '' unless ts

    ts.strftime('%Y-%m-%d %H:%M:%S UTC')
  end

  def url_escape(s)
    CGI.escape(s)
  end
end

include DOTIW::Methods

ENV['TZ'] = 'UTC'

template = Erubis::Eruby.new(File.read('config/database.yaml'))
db_config = YAML.safe_load(template.result) 
env = development? ? :development : :production
ActiveRecord::Base.establish_connection(db_config[env.to_s])
ActiveRecord::Base.logger = Logger.new($stderr) if development?

get '/' do
  @user = session[:user_id] && Tables::User.find_by(id: session[:user_id])
  service = NetList.new
  @nets = service.list
  @last_updated_at = Tables::Server.maximum(:net_list_fetched_at)
  @update_interval = 30
  erb :index
end

get '/net/:name' do
  @user = session[:user_id] && Tables::User.find_by(id: session[:user_id])
  unless @user
    redirect "/login?net=#{params[:name]}"
    return
  end

  service = NetInfo.new(CGI.unescape(params[:name]))
  @net = service.info
  @messages = @net.messages.order(:sent_at)
  @last_updated_at = @net.updated_at
  @update_interval = @net.update_interval_in_seconds
  erb :net
rescue NetInfo::NotFoundError => e
  @message = e.message
  erb :missing, status: 404
end

get '/station/:call_sign/image' do
  station = Tables::Station.find_by(call_sign: params[:call_sign])

  expires Tables::Station::EXPIRATION_IN_SECONDS, :public, :must_revalidate

  if station
    if station.image
      redirect station.image
    else
      erb 'not found', status: 401
    end
    return
  end

  unless session[:qrz_session]
    erb 'there was an error; please log out and try again', status: 401
    return
  end

  qrz = Qrz.new(session: session[:qrz_session])
  begin
    unless (image = qrz.lookup(params[:call_sign])[:image])
      erb 'not found', status: 401
      return
    end
  rescue Qrz::NotFound
    image = nil
    erb 'not found', status: 401
    return
  end

  Tables::Station.create!(
    call_sign: params[:call_sign],
    image:
  )

  redirect image
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
  session[:qrz_session] = qrz.session

  redirect params[:net] ? "/net/#{params[:net]}" : '/'
rescue Qrz::Error => e
  @error = e.message
  erb :login
end

get '/logout' do
  session.delete(:user_id)
  redirect '/'
end

def serve(url)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request(req)
  end
  content_type response.content_type
  raise response.body.inspect
end
