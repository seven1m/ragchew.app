require 'bundler/setup'

require 'sinatra'
require 'sinatra/reloader' if development?

require_relative './boot'

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
set :sessions, same_site: :strict, expire_after: 365 * 24 * 60 * 60 # 1 year

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
  @coords = Tables::Checkin.order(created_at: :desc)
              .limit(100)
              .map { |c| GridSquare.new(c.grid_square).to_a }
              .compact
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
  @last_updated_at = @net.fully_updated_at
  @update_interval = @net.update_interval_in_seconds + 1
  @coords = @checkins.map do |checkin|
    GridSquare.new(checkin.grid_square).to_a.tap do |coord|
      coord << checkin.call_sign if coord
    end
  end.compact

  if @user.monitoring_net == @net
    @user.update!(monitoring_net_last_refreshed_at: Time.now)
  end

  erb :net
rescue NetInfo::NotFoundError => e
  @message = e.message
  status 404
  erb :missing
end

get '/station/:call_sign/image' do
  call_sign = params[:call_sign]
  station = Tables::Station.find_by(call_sign:)

  if station&.expired?
    station.destroy!
    station = nil
  end

  expires Tables::Station::EXPIRATION_IN_SECONDS, :public, :must_revalidate

  if station
    if station.image
      redirect station.image
    else
      status 404
      erb 'not found'
    end
    return
  end

  qrz = QrzAutoSession.new
  begin
    if (image = qrz.lookup(call_sign)[:image])
      Tables::Station.create!(call_sign:, image:)
      redirect image
    else
      Tables::Station.create!(call_sign:, image: nil)
      status 404
      erb 'no image for this call sign'
    end
  rescue Qrz::NotFound
    Tables::Station.create!(call_sign:, image: nil)
    status 404
    erb 'call sign not found'
  rescue Qrz::Error => e
    status 500
    erb "qrz error: #{e.message}"
  end
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

  session.clear
  session[:user_id] = @user.id
  session[:qrz_session] = qrz.session

  redirect params[:net] ? "/net/#{params[:net]}" : '/'
rescue Qrz::Error => e
  @error = e.message
  erb :login
end

get '/logout' do
  session.clear
  redirect '/'
end

get '/admin/stats' do
  @user = get_user
  require_admin!

  @user_count_total = Tables::User.count
  @user_count_last_24_hours = Tables::User.where('last_signed_in_at > ?', Time.now - (24 * 60 * 60)).count
  @user_count_last_1_hour = Tables::User.where('last_signed_in_at > ?', Time.now - (1 * 60 * 60)).count
  erb :admin_stats
end

get '/admin/users' do
  @user = get_user
  require_admin!

  @users = Tables::User.order(last_signed_in_at: :desc).limit(100).to_a
  erb :admin_users
end

post '/monitor/:net_id' do
  @user = get_user
  unless @user
    redirect '/'
    return
  end

  @net_info = NetInfo.new(id: params[:net_id])
  @net = @net_info.net

  if @user.monitoring_net && @user.monitoring_net != @net
    # already monitoring one, stop stop that first
    begin
      NetInfo.new(id: @user.monitoring_net_id).stop_monitoring!(user: @user)
    rescue NetInfo::NotFoundError
      # no biggie I guess
    end
  end

  @net_info.monitor!(user: @user)

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

  @user.update!(
    monitoring_net: nil,
    monitoring_net_last_refreshed_at: nil,
  )

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
  @net = @net_info.net_without_cache_update

  if @user.monitoring_net != @net
    status 401
    return 'not monitoring this net'
  end

  @net_info.send_message!(user: @user, message: params[:message])

  session[:message_sent] = { net_id: @net.id, count_before: @net.messages.count, message: params[:message] }

  redirect "/net/#{url_escape @net.name}"
end

def get_user
  if !session[:user_id] || !(user = Tables::User.find_by(id: session[:user_id]))
    return
  end

  now = Time.now
  if user.last_signed_in_at && now - user.last_signed_in_at > 20 * 60 # 20 minutes
    user.update!(last_signed_in_at: now)
  end

  user
end

def require_admin!
  admins = ENV.fetch('ADMIN_CALL_SIGNS').split(',')
  return if @user && admins.include?(@user.call_sign)

  redirect '/'
end
