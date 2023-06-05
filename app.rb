require 'bundler/setup'

require 'sinatra'
require 'sinatra/reloader' if development?

require_relative './boot'

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
set :sessions, same_site: :lax, expire_after: 365 * 24 * 60 * 60 # 1 year

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

  def make_url_safe_for_html_attribute(s)
    s.to_s.gsub('"', '%22')
  end

  def make_value_safe_html_attribute(s)
    s.to_s.gsub('"', '&#34;')
  end

  def pretty_url(url)
    url.sub(/^https?:\/\//, '').sub(/\/$/, '')
  end

  def development?
    ENV['RACK_ENV'] == 'development'
  end

  def pluralize(word, count)
    if count == 1
      word
    else
      "#{word}s"
    end
  end

  def club_logo_image_tag(club)
    return unless club&.logo_url.present?

    "<a href=\"/group/#{url_escape(club.name)}\">" \
      "<img class='net-logo'" \
      "src=\"#{make_url_safe_for_html_attribute(club.logo_url)}\"/>" \
      "</a>"
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
BASE_URL = 'https://ragchew.app'
ONE_PIXEL_IMAGE = File.read(File.expand_path('./public/images/1x1.png', __dir__))

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
  @user = get_user

  params[:name] = CGI.unescape(params[:name])
  service = NetInfo.new(name: params[:name])

  service.update!
  @net = service.net
  @page_title = @net.name

  if @user&.monitoring_net == @net
    @user.update!(monitoring_net_last_refreshed_at: Time.now)
  end

  if @user
    @checkins = @net.checkins.order(:num).to_a
    @messages = @net.messages.order(:sent_at).to_a
    @monitors = @net.monitors.order(:call_sign).to_a
    @coords = @checkins.map do |checkin|
      GridSquare.new(checkin.grid_square).to_a.tap do |coord|
        coord << checkin.call_sign if coord
      end
    end.compact
    @favorites = @user.favorites.pluck(:call_sign)
    @last_updated_at = @net.fully_updated_at
    @update_interval = @net.update_interval_in_seconds + 1
    erb :net
  else
    @checkin_count = @net.checkins.count
    @message_count = @net.messages.count
    @monitor_count = @net.monitors.count
    erb :net_limited
  end
rescue NetInfo::NotFoundError
  @net_count = Tables::Net.count
  if Tables::BlockedNet.blocked?(params[:name])
    @name = nil
  else
    @closed_net = Tables::ClosedNet.where(name: params[:name]).order(started_at: :desc).first
    @page_title = @name = @closed_net&.name
  end
  if @closed_net
    @checkin_count = @closed_net.checkin_count
    @message_count = @closed_net.message_count
    @monitor_count = @closed_net.monitor_count
    if request.xhr?
      # force JS to reload page
      status 404
      'net is closed'
    else
      erb :closed_net
    end
  else
    status 404
    erb :missing_net
  end
end

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
  params[:net] = CGI.unescape(params[:net]) if params[:net]

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

  redirect params[:net] ? "/net/#{url_escape params[:net]}" : '/'
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

get '/admin/closed-nets' do
  @user = get_user
  require_admin!

  per_page = 20
  scope = Tables::ClosedNet.order(started_at: :desc)
  scope.where!('name like ?', '%' + params[:name] + '%') if params[:name]
  @total_count = scope.count
  scope.where!('started_at < ?', params[:started_at]) if params[:started_at]
  @more_pages = scope.count - per_page > 0
  @closed_nets = scope.limit(per_page)

  erb :admin_closed_nets
end

get '/admin/closed-net/:id' do
  @user = get_user
  require_admin!

  @net_count = Tables::Net.count
  @closed_net = Tables::ClosedNet.find(params[:id])
  @name = @closed_net&.name
  @checkin_count = @closed_net.checkin_count
  @message_count = @closed_net.message_count
  @monitor_count = @closed_net.monitor_count
  erb :closed_net
end

delete '/admin/closed-net/:id' do
  @user = get_user
  require_admin!

  Tables::ClosedNet.where(id: params[:id]).delete_all

  redirect '/admin/closed-nets'
end

get '/admin/clubs' do
  @user = get_user
  require_admin!

  scope = Tables::Club.order(:name)
  scope.where!('name like ?', '%' + params[:name] + '%') if params[:name]
  @clubs = scope.to_a

  erb :admin_clubs
end

get '/admin/clubs/new' do
  @user = get_user
  require_admin!

  @club = Tables::Club.new
  @url = "/admin/clubs"

  erb :admin_club_edit
end

get '/admin/clubs/:id/edit' do
  @user = get_user
  require_admin!

  @club = Tables::Club.find(params[:id])
  @url = "/admin/clubs/#{@club.id}"

  erb :admin_club_edit
end

post '/admin/clubs' do
  @user = get_user
  require_admin!

  @club = Tables::Club.create!(name: params[:club][:name])
  fix_club_params(params)
  @club.update!(params[:club])

  only_blank = params[:force_update_existing_nets] != 'true'
  AssociateClubWithNets.new(@club, only_blank:).call

  redirect "/admin/clubs/#{@club.id}/edit"
rescue JSON::ParserError
  status 400
  'error parsing JSON'
end

patch '/admin/clubs/:id' do
  @user = get_user
  require_admin!

  @club = Tables::Club.find(params[:id])
  fix_club_params(params)
  @club.update!(params[:club])

  only_blank = params[:force_update_existing_nets] != 'true'
  AssociateClubWithNets.new(@club, only_blank:).call

  redirect "/admin/clubs/#{@club.id}/edit"
rescue JSON::ParserError
  status 400
  'error parsing JSON'
end

delete '/admin/clubs/:id' do
  @user = get_user
  require_admin!

  @club = Tables::Club.find(params[:id])
  @club.destroy

  redirect '/admin/clubs'
end

get '/admin/table/:table' do
  @user = get_user
  require_admin!

  per_page = 100
  klass = Tables.const_get(params[:table].classify)
  scope = klass.order(:id)
  scope.where!('id > ?', params[:after]) if params[:after]
  @more_pages = scope.count > per_page
  scope.limit!(per_page)
  @records = scope.to_a
  @columns = klass.columns

  erb :admin_table
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

get '/group/:slug' do
  @user = get_user

  params[:slug] = CGI.unescape(params[:slug])
  @club = Tables::Club.find_by!(name: params[:slug])
  if @club.about_url.nil?
    status 404
    return erb :missing_club
  end
  
  @net_names = (
    @club.nets.order(:name).pluck(:name) +
    @club.closed_nets.order(:name, :started_at).pluck(:name)
  ).sort.uniq(&:downcase)

  erb :club
rescue ActiveRecord::RecordNotFound
  status 404
  erb :missing_club
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

get '/sitemap.txt' do
  content_type 'text/plain'
  names = (Tables::Net.pluck(:name) + Tables::ClosedNet.distinct(:name).pluck(:name)).uniq
  blocked_net_names = Tables::BlockedNet.pluck(:name)
  names.reject! do |name|
    Tables::BlockedNet.blocked?(name, names: blocked_net_names)
  end
  [
    "#{BASE_URL}/",
    names.map { |name| "#{BASE_URL}/net/#{url_escape(name)}" },
    Tables::Club.where.not(about_url: nil).pluck(:name).map { |name| "#{BASE_URL}/group/#{url_escape(name)}" },
  ].flatten.join("\n")
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

def fix_club_params(params)
  %i[full_name description logo_url about_url].each do |param|
    params[:club][param] = params[:club][param].presence
  end
  %i[net_patterns net_list].each do |param|
    params[:club][param] = JSON.parse(params[:club][param]) if params[:club][param]
  end
  params[:club][:logo_url] = UpdateClubList.download_logo_url(@club, params[:club][:logo_url])
end
