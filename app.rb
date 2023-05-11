require 'bundler/setup'

require 'sinatra'
require 'sinatra/reloader' if development?

require_relative './boot'

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
set :sessions do
  { same_site: :strict }
end

set :static_cache_control, [:public, max_age: 60]

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

  def development?
    ENV['RACK_ENV'] == 'development'
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
  @user = get_user
  service = NetList.new
  @nets = service.list
  @last_updated_at = Tables::Server.maximum(:net_list_fetched_at)
  @update_interval = 30
  @update_backoff = 5
  erb :index
end

get '/net/:name' do
  @user = get_user
  unless @user
    redirect "/login?net=#{params[:name]}"
    return
  end

  service = NetInfo.new(name: CGI.unescape(params[:name]))
  @net = service.net
  @checkins = @net.checkins.order(:num).to_a
  @messages = @net.messages.order(:sent_at).to_a
  @monitors = @net.monitors.order(:call_sign).to_a
  @last_updated_at = @net.updated_at
  @update_interval = @net.update_interval_in_seconds + 1

  if @user.monitoring_net == @net
    @user.update!(monitoring_net_last_refreshed_at: Time.now)
  end

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
  @user.last_signed_in_at = Time.now
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

get '/admin/stats' do
  @user = get_user

  if @user&.call_sign != 'KI5ZDF'
    redirect '/'
    return
  end

  @user_count_total = Tables::User.count
  @user_count_last_24_hours = Tables::User.where('last_signed_in_at > ?', Time.now - (24 * 60 * 60)).count
  @user_count_last_1_hour = Tables::User.where('last_signed_in_at > ?', Time.now - (1 * 60 * 60)).count
  erb :admin_stats
end

post '/monitor/:net_id' do
  @user = get_user
  unless @user
    redirect '/'
    return
  end

  @net_info = NetInfo.new(id: params[:net_id])
  @net_info.monitor!(user: @user)

  @net = @net_info.net

  @user.update!(monitoring_net: @net)

  redirect "/net/#{url_escape @net.name}#messages"
end

post '/unmonitor/:net_id' do
  @user = get_user
  unless @user
    redirect '/'
    return
  end

  @net_info = NetInfo.new(id: params[:net_id])
  @net_info.stop_monitoring!(user: @user)

  @net = @net_info.net

  @user.update!(monitoring_net: nil)

  redirect "/net/#{url_escape @net.name}#messages"
end

post '/message/:net_id' do
  @user = get_user
  unless @user
    redirect '/'
    return
  end

  if params[:message].to_s.strip.empty?
    status 400
    return 'no message sent'
  end

  @net_info = NetInfo.new(id: params[:net_id])
  @net_info.send_message!(user: @user, message: params[:message])

  @net = @net_info.net_without_cache_update

  session[:message_sent] = { net_id: @net.id, count_before: @net.messages.count, message: params[:message] }

  redirect "/net/#{url_escape @net.name}"
end

def get_user
  if !session[:user_id] || !(user = Tables::User.find_by(id: session[:user_id]))
    return
  end

  # seems that QRZ sessions don't last very long :-(
  now = Time.now
  login_expiration_in_seconds = 4 * 60 * 60
  if user.last_signed_in_at && now - user.last_signed_in_at > login_expiration_in_seconds
    session.delete(:user_id)
    session.delete(:qrz_session)
    redirect '/'
    return
  end

  user
end
