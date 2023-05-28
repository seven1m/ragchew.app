require 'bundler/setup'

require 'sinatra'
require 'sinatra/reloader' if development?

require_relative './boot'

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
set :sessions, same_site: :strict, expire_after: 365 * 24 * 60 * 60 # 1 year

set :static_cache_control, [:public, max_age: 60]

set :bind, '0.0.0.0'

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

MAX_FAVORITES = 50

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
  @centers = @nets.map do |net|
    next unless net.show_circle?
    {
      latitude: net.center_latitude,
      longitude: net.center_longitude,
      radius: net.center_radius,
      name: net.name,
      url: "/net/#{url_escape(net.name)}",
    }
  end.compact.sort_by { |c| c[:radius] }.reverse
  erb :index
end

get '/net/:name' do
  params[:name] = CGI.unescape(params[:name])
  service = NetInfo.new(name: params[:name])

  @user = get_user
  unless @user
    redirect "/login?net=#{params[:name]}"
    return
  end

  service.update!
  @net = service.net
  @page_title = @net.name
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
  @favorites = @user.favorites.pluck(:call_sign)

  if @user.monitoring_net == @net
    @user.update!(monitoring_net_last_refreshed_at: Time.now)
  end

  erb :net
rescue NetInfo::NotFoundError
  @closed_net = Tables::ClosedNet.where(name: params[:name]).order(started_at: :desc).first
  @name = @closed_net.name
  if Tables::BlockedNet.where(name: @closed_net.name).any?
    @closed_net = nil
    @name = nil
  end
  @net_count = Tables::Net.count
  status 404 unless @closed_net
  erb :closed_net
end

ONE_PIXEL_IMAGE = File.read(File.expand_path('./public/images/1x1.png', __dir__))

get '/station/:call_sign/image' do
  call_sign = params[:call_sign]
  station = Tables::Station.find_by(call_sign:)

  expires Tables::Station::EXPIRATION_IN_SECONDS, :public, :must_revalidate

  if station && station.image && !station.image_expired?
    if station.image == 'none'
      content_type 'image/png'
      return ONE_PIXEL_IMAGE
    else
      redirect station.image
      return
    end
  end

  qrz = QrzAutoSession.new
  begin
    if (image = qrz.lookup(call_sign)[:image])
      Tables::Station.find_or_initialize_by(call_sign:).expire_image.update!(image:)
      redirect image
    else
      Tables::Station.find_or_initialize_by(call_sign:).expire_image.update!(image: 'none')
      content_type 'image/png'
      return ONE_PIXEL_IMAGE
    end
  rescue Qrz::NotFound
    Tables::Station.find_or_initialize_by(call_sign:).expire_image.update!(image: 'none')
    content_type 'image/png'
    return ONE_PIXEL_IMAGE
  rescue Qrz::Error => e
    status 500
    erb "qrz error: #{e.message}"
  end
end

get '/favorites' do
  @page_title = 'Favorites'
  @user = get_user
  unless @user
    redirect '/'
    return
  end

  @favorites = @user.favorites.order(:call_sign).to_a

  erb :favorites
end

# from form
post '/favorite' do
  @user = get_user
  unless @user
    redirect '/'
    return
  end

  if @user.favorites.count >= MAX_FAVORITES
    status 400
    erb "<p><em>You cannot have more than #{MAX_FAVORITES} favorites.</em></p>"
  end

  station = QrzAutoSession.new.lookup(params[:call_sign])

  @user.favorites.create!(
    call_sign: station[:call_sign],
    first_name: station && station[:first_name],
    last_name: station && station[:last_name],
  )

  redirect '/favorites'
rescue ActiveRecord::RecordNotUnique
  redirect '/favorites'
rescue Qrz::NotFound
  status 400
  erb "<p><em>That call sign was not found in QRZ.</em></p>"
end

# from JS
post '/favorite/:call_sign' do
  @user = get_user

  content_type 'application/json'

  return { error: 'not logged in' }.to_json unless @user

  if @user.favorites.count >= MAX_FAVORITES
    return {
      error: "ERROR: You cannot have more than #{MAX_FAVORITES} favorites."
    }.to_json
  end

  begin
    station = QrzAutoSession.new.lookup(params[:call_sign])
  rescue Error
  end

  @user.favorites.create!(
    call_sign: station[:call_sign],
    first_name: station && station[:first_name],
    last_name: station && station[:last_name],
  )

  {
    html: erb(
      :_favorite,
      locals: { call_sign: params[:call_sign], favorited: true },
      layout: false
    )
  }.to_json
end

post '/unfavorite/:call_sign' do
  @user = get_user

  content_type 'application/json'

  return { error: 'not logged in' }.to_json unless @user

  @user.favorites.where(call_sign: params[:call_sign]).delete_all

  {
    html: erb(
      :_favorite,
      locals: { call_sign: params[:call_sign], favorited: false },
      layout: false
    )
  }.to_json
end

get '/login' do
  @page_title = 'Log in'
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
  @user.update!(result.slice(:call_sign, :first_name, :last_name, :image))

  session.clear
  session[:user_id] = @user.id
  session[:qrz_session] = qrz.session

  redirect params[:net] ? "/net/#{params[:net]}" : '/'
rescue Qrz::Error => e
  @error = e.message
  erb :login
end

get '/logout' do
  erb :logout
end

post '/logout' do
  session.clear
  redirect '/'
end

get '/admin/stats' do
  @user = get_user
  require_admin!

  redirect '/admin/users'
end

get '/admin' do
  @user = get_user
  require_admin!

  @page_title = 'Admin'
  erb :admin
end

get '/admin/users' do
  @user = get_user
  require_admin!

  @page_title = 'Admin'
  @users = Tables::User.order(last_signed_in_at: :desc).limit(100).to_a
  @user_count_total = Tables::User.count
  @user_count_last_24_hours = Tables::User.where('last_signed_in_at > ?', Time.now - (24 * 60 * 60)).count
  @user_count_last_1_hour = Tables::User.where('last_signed_in_at > ?', Time.now - (1 * 60 * 60)).count
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
    # already monitoring one, so stop that first
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

  @user.update!(
    monitoring_net: nil,
    monitoring_net_last_refreshed_at: nil,
  )

  @net_info = NetInfo.new(id: params[:net_id])
  @net_info.stop_monitoring!(user: @user)

  @net = @net_info.net

  redirect "/net/#{url_escape @net.name}#messages"
rescue NetInfo::NotFoundError
  # net must have closed so just go home
  redirect '/'
end

post '/message/:net_id' do
  @user = get_user
  unless @user
    redirect '/'
    return
  end

  message = params[:message].to_s.strip
    .tr("‘ʼ’", "'")
    .tr("“”", '"')
    .tr("-–—−⁃᠆", "-")
    .gsub("…", "...")

  message_with_silly_encoding = message.encode('ISO-8859-1', invalid: :replace, undef: :replace)
  message = message_with_silly_encoding.encode('UTF-8', invalid: :replace, undef: :replace)

  if message_with_silly_encoding.empty?
    status 400
    return 'no message sent'
  end

  @net_info = NetInfo.new(id: params[:net_id])
  @net = @net_info.net

  if @user.monitoring_net != @net
    status 401
    return 'not monitoring this net'
  end

  @net_info.send_message!(user: @user, message: message_with_silly_encoding)

  session[:message_sent] = { net_id: @net.id, count_before: @net.messages.count, message: }

  redirect "/net/#{url_escape @net.name}"
end

post '/admin/block_net' do
  @user = get_user
  require_admin!

  Tables::BlockedNet.create!(name: CGI.unescape(params[:name]), reason: params[:reason])
  redirect '/admin#blocked-nets'
end

post '/admin/unblock_net' do
  @user = get_user
  require_admin!

  Tables::BlockedNet.where(name: CGI.unescape(params[:name])).delete_all
  redirect '/admin#blocked-nets'
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
