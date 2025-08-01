require 'bundler/setup'

require 'sinatra'
require 'sinatra/reloader' if development?

require_relative './boot'

disable :protection
enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
set :sessions, same_site: :lax, expire_after: 365 * 24 * 60 * 60 # 1 year

set :static_cache_control, [:public, max_age: 60]

set :bind, '0.0.0.0'

CREATE_NET_REQUIRED_PARAMS = {
  club_id: {},
  net_name: { length: 32, format: /\A[A-Za-z0-9][A-Za-z0-9 \(\)-]*\z/, message: 'Net name must contain only letters, numbers, spaces, parentheses, and/or hyphens, and must start with a letter or number.' },
  net_password: { length: 20 },
  frequency: { length: 16 },
  band: { length: 10 },
  mode: { length: 10 },
  net_control: { length: 20 },
}

if development?
  Dir['./lib/**/*.rb'].each do |path|
    also_reload(path)
  end
end

helpers do
  def nav
    if @user
      links = [
        "<a href='/user'>#{erb "<%== @user.call_sign %>"}</a>",
        @user.admin? ? "<a href='/admin'>admin</a>" : nil,
        !@user.logging_net ? "<a href='/create-net'>create net</a>" : nil,
        "<a href='/logout' data-method='post'>log out</a>"
      ].compact
    else
      links = [
        "<a href='/login'>log in</a>"
      ]
    end
    if @user&.logging_net && @net != @user.logging_net
      links << "logging: <a href='/net/#{url_escape @user.logging_net.name}' class='warning'>#{erb "<%== @user.logging_net.name %>"}</a>"
    end
    erb :_nav, locals: { links: }
  end

  def format_time(ts, time_only: false)
    return '' unless ts

    "<span class='time #{time_only ? 'time-only' : ''}' data-time='#{ts.strftime('%Y-%m-%dT%H:%M:%S.000Z')}'>#{ts.strftime('%Y-%m-%d %H:%M:%S UTC')}</span>"
  end

  def url_escape(s)
    CGI.escape(s.to_s)
  end

  def make_url_safe_for_html_attribute(s)
    s.to_s.gsub('"', '%22')
  end

  def make_value_safe_for_html_attribute(s)
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

  def club_logo_image_tag(club, class_name: nil)
    return unless club&.logo_url.present?

    "<a href=\"/group/#{url_escape(club.name)}\">" \
      "<img class='club-logo #{class_name}'" \
      "src=\"#{make_url_safe_for_html_attribute(club.logo_url)}\"/>" \
      '</a>'
  end

  def is_admin?
    @user&.admin?
  end

  def has_net_logger_role?
    @user&.net_logger?
  end

  def json_for_html_attribute(hash)
    hash.to_json.gsub('&', '&amp;').gsub('"', '&quot;')
  end

  def script_tag(filename)
    ts = File.stat(File.join('public', filename)).mtime.to_i
    "<script type=\"module\" src=\"/#{filename}?_ts=#{ts}\"></script>"
  end

  def style_tag(filename)
    ts = File.stat(File.join('public', filename)).mtime.to_i
    "<link rel=\"stylesheet\" href=\"/#{filename}?_ts=#{ts}\"/>"
  end

  def pusher_url
    @pusher_url ||= URI.parse(ENV.fetch('PUSHER_URL'))
  end

  def pusher_key = pusher_url.user

  def pusher_cluster
    @pusher_cluster ||= pusher_url.host.split('.').first.split('-').last
  end

  def club_noun
    if @club && @club.full_name.to_s =~ /club/i
      'club'
    else
      'group'
    end
  end

  def hours_in_range(range)
    return to_enum(__method__, range) unless block_given?

    t = range.begin.beginning_of_hour
    while t < range.end
      yield t
      t += 1.hour
    end
  end

  def dates_in_range(range)
    return to_enum(__method__, range) unless block_given?

    t = range.begin.beginning_of_day
    while t < range.end
      yield t
      t = (t + 1.day).beginning_of_day
    end
  end

  def weeks_in_range(range)
    return to_enum(__method__, range) unless block_given?

    t = range.begin.beginning_of_week
    while t < range.end
      yield t
      t = (t + 1.week).beginning_of_week
    end
  end

  def stat_values_by_week(weeks, name)
    records = Tables::Stat.where(name:, period: weeks).to_a
    weeks.map do |week|
      records.detect { |r| r.period == week.beginning_of_week }&.value || 0
    end
  end

  def sort_heading(column, label, other_attributes = [])
    query = other_attributes.map do |attr|
      "#{attr}=#{url_escape params[attr]}"
    end.join('&')
    direction = params[:sort].to_s =~ /^#{column}(?! desc)/ ? 'desc' : 'asc'
    if params[:sort].to_s.start_with?(column)
      arrow = direction == 'asc' ? '↑' : '↓'
    end
    "<a href=\"?#{query}&sort=#{column} #{direction}\">#{label}</a> #{arrow}"
  end
end

include DOTIW::Methods

ENV['TZ'] = 'UTC'

MAX_FAVORITES = 50
BASE_URL = ENV['BASE_URL'] || 'https://ragchew.app'
SUPPORT_EMAIL = ENV['SUPPORT_EMAIL'] || 'tim@timmorgan.org'
ONE_PIXEL_IMAGE = File.read(File.expand_path('./public/images/1x1.png', __dir__))

get '/' do
  @homepage = true
  @user = get_user
  frequency_order_cast = Arel.sql('CAST(frequency AS DOUBLE)')
  band_order_cast = Arel.sql("CAST(REPLACE(REPLACE(band, '70cm', '0'), 'm', '') AS UNSIGNED)")
  order = case params[:order]
          when 'name', nil
            { name: :asc }
          when 'frequency'
            { frequency_order_cast => :asc }
          when 'mode,frequency'
            { mode: :asc, frequency_order_cast => :asc }
          when 'band,frequency'
            { band_order_cast => :asc, frequency_order_cast => :asc }
          when 'started_at'
            { started_at: :desc }
          end
  service = NetList.new
  @nets = service.list(order:)
  @last_updated_at = Tables::Server.maximum(:net_list_fetched_at)
  @update_interval = 30
  @update_backoff = 5
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

get '/about' do
  @user = get_user

  erb :about
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
    @messages = @net.messages.order(:sent_at).to_a
    @monitors = @net.monitors.order(:call_sign).to_a
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

get '/net/:id/details' do
  @user = get_user
  require_user!

  service = NetInfo.new(id: params[:id])

  service.update!
  net = service.net

  checkins = net.checkins.order(:num).to_a
  coords = checkins.filter_map do |checkin|
    lat, lon = GridSquare.new(checkin.grid_square).to_a
    if lat && lon
      { lat:, lon:, callSign: checkin.call_sign, name: checkin.name }
    end
  end

  monitoring_this_net = @user.monitoring_net == net
  if monitoring_this_net
    @user.update!(monitoring_net_last_refreshed_at: Time.now)
  end

  messagesCount = net.messages.count
  messages = monitoring_this_net ? net.messages.order(:sent_at).to_a : []
  messages.reject! { |m| m.blocked? && m.call_sign.upcase != @user.call_sign.upcase }
  monitors = net.monitors.order(:call_sign).to_a
  favorites = @user.favorites.pluck(:call_sign)

  content_type 'application/json'
  {
    checkins:,
    coords:,
    messages:,
    messagesCount:,
    monitors:,
    favorites:,
    lastUpdatedAt: net.updated_at.rfc3339,
    monitoringThisNet: monitoring_this_net,
  }.to_json
rescue NetInfo::NotFoundError
  status 404
  content_type 'application/json'
  { error: 'net not found' }.to_json
end

get '/net/:id/log' do
  @user = get_user
  require_user!

  service = NetInfo.new(id: params[:id])

  content_type 'text/plain'
  attachment "#{service.net.name}.log"
  service.to_log
rescue NetInfo::NotFoundError
  status 404
  erb :missing_net
end

get '/create-net' do
  @user = get_user
  check_if_already_started_a_net!(@user)

  @my_clubs = @user.clubs
  erb :create_net
end

post '/create-net' do
  @user = get_user
  require_net_logger_role!

  check_if_already_started_a_net!(@user)

  content_type 'application/json'
  @params = params.merge(JSON.parse(request.body.read))

  missing = CREATE_NET_REQUIRED_PARAMS.keys.reject do |param|
    params[param].present?
  end

  if missing.any?
    status 400
    return { error: "Some required fields are missing: #{missing.join(', ')}.", fields: missing }.to_json
  end

  club = Tables::Club.find(params[:club_id])
  unless club.club_members.where(user_id: @user.id).any?
    status 400
    return { error: 'You are not a member of this club.' }.to_json
  end

  CREATE_NET_REQUIRED_PARAMS.each do |param, requirements|
    next unless (length = requirements[:length])

    if params[param].size > length
      status 400
      return { error: "#{param} is too long.", fields: [param] }.to_json
    end
  end

  CREATE_NET_REQUIRED_PARAMS.each do |param, requirements|
    next unless (format = requirements[:format])

    if params[param] !~ format
      status 400
      return { error: "#{param} contains characters not allowed.", fields: [param] }.to_json
    end
  end

  if Tables::Net.where(name: params[:net_name]).exists?
    status 400
    return { error: 'A net with this name is already in progress.', fields: [:net_name] }.to_json
  end

  NetLogger.create_net!(
    club:,
    name: params[:net_name],
    password: params[:net_password],
    frequency: params[:frequency],
    net_control: params[:net_control],
    user: @user,
    mode: params[:mode],
    band: params[:band],
  )

  NetInfo.new(name: params[:net_name]).monitor!(user: @user)

  redirect "/net/#{url_escape params[:net_name]}"
end

post '/start-logging/:id' do
  @user = get_user
  require_net_logger_role!

  if @user.logging_net
    halt 401, 'already logging a net'
  end

  @net = Tables::Net.find(params[:id])
  unless @user.can_log_for_club?(@net.club)
    halt 401, 'not authorized'
  end

  net_info = NetInfo.new(id: @net.id)
  NetLogger.start_logging(net_info, password: params[:net_password], user: @user)
  redirect "/net/#{url_escape net_info.name}"
rescue NetLogger::PasswordIncorrectError
  halt 401, 'incorrect password'
end

post '/stop-logging/:id' do
  @user = get_user
  require_user!

  @user.update!(logging_net: nil, logging_password: nil)
  @net = Tables::Net.find(params[:id])
  redirect "/net/#{url_escape @net.name}"
rescue ActiveRecord::RecordNotFound
  redirect '/'
end

patch '/log/:id/:num' do
  @user = get_user
  require_net_logger_role!

  @params = params.merge(JSON.parse(request.body.read))

  logger = NetLogger.new(NetInfo.new(id: params[:id]), user: @user)
  logger.update!(params.fetch(:num).to_i, params)

  content_type 'application/json'
  return { success: true }.to_json
rescue NetLogger::NotAuthorizedError
  halt 401, 'not authorized'
end

delete '/log/:id/:num' do
  @user = get_user
  require_net_logger_role!

  logger = NetLogger.new(NetInfo.new(id: params[:id]), user: @user)
  logger.delete!(params.fetch(:num).to_i)

  return { success: true }.to_json
rescue NetLogger::NotAuthorizedError
  halt 401, 'not authorized'
end

patch '/highlight/:id/:num' do
  @user = get_user
  require_net_logger_role!

  logger = NetLogger.new(NetInfo.new(id: params[:id]), user: @user)
  requested_num = params.fetch(:num).to_i

  if logger.current_highlight_num == requested_num
    highlight_num = 0
  else
    highlight_num = requested_num
  end

  logger.highlight!(highlight_num)

  return { success: true }.to_json
rescue NetLogger::NotAuthorizedError
  halt 401, 'not authorized'
end

post '/close-net/:id' do
  @user = get_user
  require_net_logger_role!

  logger = NetLogger.new(NetInfo.new(id: params[:id]), user: @user)
  logger.close_net!

  @user.update!(
    monitoring_net: nil,
    monitoring_net_last_refreshed_at: nil,
    logging_net: nil,
    logging_password: nil,
  )

  redirect '/'
rescue NetLogger::NotAuthorizedError
  halt 401, 'not authorized'
rescue NetLogger::CouldNotCloseNetError => e
  halt 400, "there was an error closing this net: #{e.message}"
end

get '/closed-nets' do
  @user = get_user

  params[:days] ||= '1'

  scope = Tables::ClosedNet.all
  if params[:days] != 'all'
    days = params[:days].to_i
    scope = scope.where('started_at > ?', Time.now - (days * 24 * 60 * 60))
  end

  sort_name, sort_direction = params[:sort].to_s.split(' ', 2)
  sort_name = 'name' unless %w[name frequency band mode started_at].include?(sort_name)
  sort_direction = 'asc' unless %w[asc desc].include?(sort_direction)
  sort = { sort_name => sort_direction }
  if sort_name == 'started_at'
    sort[:name] = 'asc'
  else
    sort[:started_at] = 'asc'
  end
  params[:sort] = "#{sort_name} #{sort_direction}"
  scope = scope.order(sort)

  if params[:name].present?
    scope = scope.where('name like :name or frequency like :name', { name: "%#{params[:name].gsub(/%/, '\%')}%" })
  end

  @closed_nets = scope

  @total_days = ((Time.now - Tables::ClosedNet.order(:started_at).first.started_at) / 60 / 60 / 24).ceil
  @total_count = @closed_nets.count
  @closed_nets = @closed_nets.offset(params[:offset])
  @per_page = 100
  @more_pages = @closed_nets.count > @per_page
  @closed_nets = @closed_nets.limit(@per_page)

  erb :closed_nets
end

get '/closed-net/:id' do
  @user = get_user

  @closed_net = Tables::ClosedNet.find(params[:id])
  @page_title = @name = @closed_net&.name
  @checkin_count = @closed_net.checkin_count
  @message_count = @closed_net.message_count
  @monitor_count = @closed_net.monitor_count
  @net_count = Tables::Net.count

  @more_recent_closed_net = Tables::ClosedNet.where(name: @closed_net.name).where('started_at > ?', @closed_net.started_at).order(started_at: :desc).first
  @open_net = Tables::Net.find_by(name: @closed_net.name)

  erb :closed_net
rescue ActiveRecord::RecordNotFound
  status 404
  erb :missing_net
end

get '/groups' do
  @clubs = Tables::Club.order_by_name.pluck(:name, :full_name)

  erb :clubs
end

post '/join-group/:id' do
  @user = get_user
  require_user!

  @club = Tables::Club.find(params[:id])
  @club.club_members.create!(user: @user)

  redirect "/group/#{url_escape @club.name}"
end

post '/leave-group/:id' do
  @user = get_user
  require_user!

  @club = Tables::Club.find(params[:id])
  @club.club_members.where(user_id: @user.id).delete_all

  if params[:return] == '/user'
    redirect '/user'
  else
    redirect "/group/#{url_escape @club.name}"
  end
end

get '/station/:call_sign' do
  @user = get_user
  require_net_logger_role!

  content_type 'application/json'

  begin
    station = StationUpdater.new(params[:call_sign]).call
  rescue StationUpdater::NotFound => e
    status 404
    return { 'error' => e.message }.to_json
  rescue Qrz::Error => e
    status 500
    return { 'error' => e.message }.to_json
  end

  attributes = station.attributes

  if (club_station = params[:club_id] && Tables::ClubStation.where(club_id: params[:club_id], call_sign: params[:call_sign]).first)
    attributes.merge!(club_station.attributes.slice('preferred_name', 'notes'))
  end

  attributes.to_json
end

get '/station/:call_sign/image' do
  @user = get_user
  require_user!

  expires Tables::Station::EXPIRATION_IN_SECONDS, :public, :must_revalidate

  begin
    station = StationUpdater.new(params[:call_sign]).call
  rescue StationUpdater::NotFound
    content_type 'image/png'
    return ONE_PIXEL_IMAGE
  rescue Qrz::Error => e
    status 500
    return erb("qrz error: #{e.message}")
  end

  image_url = station.image.presence

  unless image_url
    content_type 'image/png'
    return ONE_PIXEL_IMAGE
  end

  redirect image_url
end

# from form
post '/favorite' do
  @user = get_user
  require_user!

  if @user.favorites.count >= MAX_FAVORITES
    status 400
    erb "<p><em>You cannot have more than #{MAX_FAVORITES} favorites.</em></p>"
  end

  begin
    station = QrzAutoSession.new.lookup(params[:call_sign])
  rescue Qrz::Error
  end

  @user.favorites.create!(
    call_sign: station ? station[:call_sign] : params[:call_sign].upcase,
    first_name: station && station[:first_name],
    last_name: station && station[:last_name],
  )

  redirect '/user'
rescue ActiveRecord::RecordNotUnique
  redirect '/user'
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
  rescue Qrz::Error
  end

  @user.favorites.create!(
    call_sign: station ? station[:call_sign] : params[:call_sign].upcase,
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

get '/user' do
  @user = get_user
  require_user!

  @my_clubs = @user.clubs.order_by_name
  @favorites = @user.favorites.order(:call_sign).to_a

  @page_title = 'User Profile and Settings'
  erb :user
end

post '/preferences' do
  @user = get_user
  require_user!

  @user.time_format = params[:time_format]
  @user.theme = params[:theme]
  @user.save!

  redirect '/'
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

def gather_weekly_stats
  Time.zone = 'America/Chicago'

  time_range = 1.year.ago..Time.zone.now
  weeks = weeks_in_range(time_range).to_a

  new_user_values = stat_values_by_week(weeks, 'new_users_per_week')
  active_user_values = stat_values_by_week(weeks, 'active_users_per_week').zip(new_user_values).map { |active, new| active - new }
  @user_stats_weekly = {
    new_users: {
      x: weeks,
      y: new_user_values,
      name: 'new',
      type: 'bar'
    },
    active_users: {
      x: weeks,
      y: active_user_values,
      name: 'existing',
      type: 'bar'
    }
  }
end

get '/admin' do
  @user = get_user
  require_admin!

  @page_title = 'Admin'

  gather_weekly_stats

  erb :admin
end

get '/admin/users' do
  @user = get_user
  require_admin!

  @page_title = 'Admin - Users'

  @per_page = 100

  order = case params[:order]
          when 'call_sign'
            { call_sign: :asc }
          when 'first_name,last_name'
            { first_name: :asc, last_name: :asc }
          when 'created_at'
            { created_at: :desc }
          when 'last_signed_in_at', nil
            { last_signed_in_at: :desc }
          end
  scope = Tables::User.order(order)
  scope = scope.where('call_sign like ?', '%' + params[:call_sign] + '%') if params[:call_sign]
  scope = scope.offset(params[:offset]) if params[:offset]
  @more_pages = scope.count > @per_page
  scope = scope.limit(@per_page)
  @users = scope.to_a
  @user_count_total = Tables::User.count
  @user_count_last_30_days = Tables::User.where('last_signed_in_at > ?', Time.now - (30 * 24 * 60 * 60)).count
  @user_count_last_7_days = Tables::User.where('last_signed_in_at > ?', Time.now - (7 * 24 * 60 * 60)).count
  @user_count_last_24_hours = Tables::User.where('last_signed_in_at > ?', Time.now - (24 * 60 * 60)).count
  @user_count_last_1_hour = Tables::User.where('last_signed_in_at > ?', Time.now - (1 * 60 * 60)).count

  erb :admin_users
end

get '/admin/users/:id' do
  @user = get_user
  require_admin!

  @page_title = 'Admin - User'
  @user_to_edit = Tables::User.find(params[:id])
  @club_members = @user_to_edit.club_members.includes(:club).order('clubs.name').to_a
  erb :admin_user
end

post '/admin/users/:id' do
  @user = get_user
  require_admin!

  @user_to_edit = Tables::User.find(params[:id])
  @user_to_edit.admin = params[:admin] == 'true'
  @user_to_edit.net_logger = params[:net_logger] == 'true'
  @user_to_edit.save!

  redirect "/admin/users/#{params[:id]}"
end

post '/admin/users/:id/clubs' do
  @user = get_user
  require_admin!

  @user_to_edit = Tables::User.find(params[:id])
  @club = Tables::Club.find(params[:club_id])

  # Check if user is already a member
  existing_membership = @club.club_members.find_by(user_id: @user_to_edit.id)
  if existing_membership
    # User is already a member, just redirect back
    redirect "/admin/users/#{@user_to_edit.id}#clubs"
  else
    @club.club_members.create!(user: @user_to_edit)
    redirect "/admin/users/#{@user_to_edit.id}#clubs"
  end
rescue ActiveRecord::RecordNotFound
  status 404
  return { error: 'Club or user not found.' }.to_json
end

delete '/admin/users/:id/clubs/:club_id' do
  @user = get_user
  require_admin!

  @user_to_edit = Tables::User.find(params[:id])
  @club = Tables::Club.find(params[:club_id])
  @member = @club.club_members.find_by!(user_id: @user_to_edit.id)
  @member.destroy

  redirect "/admin/users/#{@user_to_edit.id}#clubs"
rescue ActiveRecord::RecordNotFound
  status 404
  return { error: 'Membership not found.' }.to_json
end

get '/admin/users/:id/qrz' do
  @user = get_user
  require_admin!

  @user_to_edit = Tables::User.find(params[:id])
  
  begin
    station = QrzAutoSession.new.lookup(@user_to_edit.call_sign)
    
    # Add calculated lat/lon coordinates if grid square is available
    if station[:grid_square]
      lat, lon = GridSquare.new(station[:grid_square]).to_a
      if lat && lon
        station[:latitude] = lat
        station[:longitude] = lon
      end
    end
    
    station.to_json
  rescue Qrz::NotFound
    status 404
    return { error: 'Call sign not found in QRZ database.' }.to_json
  rescue Qrz::Error => e
    status 500
    return { error: "QRZ lookup failed: #{e.message}" }.to_json
  rescue => e
    status 500
    return { error: "Unexpected error: #{e.message}" }.to_json
  end
end

get '/admin/closed-nets' do
  @user = get_user
  require_admin!

  per_page = 20
  scope = Tables::ClosedNet.order(started_at: :desc)
  scope = scope.where('name like ?', '%' + params[:name] + '%') if params[:name]
  @total_count = scope.count
  scope = scope.where('started_at < ?', params[:started_at]) if params[:started_at]
  @more_pages = scope.count - per_page > 0
  @closed_nets = scope.limit(per_page)

  erb :admin_closed_nets
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
  scope = scope.where(
    'name like :query or full_name like :query',
    query: '%' + params[:name] + '%'
  ) if params[:name]
  @clubs = scope.to_a

  erb :admin_clubs
end

get '/admin/clubs/search' do
  @user = get_user
  require_admin!

  query = params[:q].to_s.strip
  if query.length < 2
    return [].to_json
  end

  clubs = Tables::Club.where(
    'name like :query or full_name like :query',
    query: '%' + query + '%'
  ).order(:name).limit(10).select(:id, :name, :full_name)

  clubs.to_json
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
  @club_members = @club.club_members.includes(:user).order('users.call_sign').to_a

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
  AssociateNetWithClub.clear_clubs_cache

  redirect "/admin/clubs/#{@club.id}/edit"
rescue JSON::ParserError
  status 400
  'error parsing JSON'
rescue ActiveRecord::RecordInvalid => e
  status 400
  e.message
end

patch '/admin/clubs/:id' do
  @user = get_user
  require_admin!

  @club = Tables::Club.find(params[:id])
  fix_club_params(params)
  @club.update!(params[:club])

  only_blank = params[:force_update_existing_nets] != 'true'
  AssociateClubWithNets.new(@club, only_blank:).call
  AssociateNetWithClub.clear_clubs_cache

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

post '/admin/clubs/:id/members' do
  @user = get_user
  require_admin!

  @club = Tables::Club.find(params[:id])
  user_to_add = Tables::User.find_by!(call_sign: params[:call_sign])
  @club.club_members.create!(user: user_to_add)

  redirect "/admin/clubs/#{@club.id}/edit#members"
rescue ActiveRecord::RecordNotFound
  status 404
  'user not found'
end

delete '/admin/clubs/:id/members/:user_id' do
  @user = get_user
  require_admin!

  @club = Tables::Club.find(params[:id])
  @member = @club.club_members.find_by!(user_id: params[:user_id])
  @member.destroy

  redirect "/admin/clubs/#{@club.id}/edit#members"
rescue ActiveRecord::RecordNotFound
  status 404
  'user not found'
end

get '/admin/nets' do
  @user = get_user
  require_admin!

  @nets = Tables::Net.includes(:club).order(:name).to_a
  @clubs = Tables::Club.order(:name).to_a

  erb :admin_nets
end

get '/admin/nets/:id' do
  @user = get_user
  require_admin!

  net = Tables::Net.find(params[:id])
  redirect "/net/#{url_escape net.name}"
end

delete '/admin/nets/:id' do
  @user = get_user
  require_admin!

  Tables::Net.find(params[:id]).destroy

  redirect '/admin/nets'
end

post '/admin/refresh-net-list' do
  @user = get_user
  require_admin!

  NetList.new.list

  redirect '/admin/nets'
end

post '/admin/batch-edit-nets' do
  @user = get_user
  require_admin!

  nets = Tables::Net.where(id: params[:net_ids])
  case params[:action]
  when 'associate club'
    if params[:club_id].blank?
      nets.update_all(club_id: nil)
    else
      club = Tables::Club.find(params[:club_id])
      nets.update_all(club_id: club.id)
    end
  when 'delete nets'
    nets.delete_all
  else
    raise "unexpected batch action: #{params[:action]}"
  end

  redirect '/admin/nets'
end

post '/admin/associate-clubs' do
  @user = get_user
  require_admin!

  Tables::Club.find_each do |club|
    AssociateClubWithNets.new(
      club,
      only_blank: true,
      created_seconds_ago: 60 * 60,
    ).call
  end

  redirect '/admin/nets'
end

get '/admin/table/:table' do
  @user = get_user
  require_admin!

  per_page = 100
  klass = Tables.const_get(params[:table].classify)
  scope = klass.order(:id)
  scope = scope.where('id > ?', params[:after]) if params[:after]
  if params[:column].present? && params[:value].present?
    column = ActiveRecord::Base.connection.quote_column_name(params[:column])
    if params[:like]
      operator = 'like'
      params[:value] = "%#{params[:value]}%" unless params[:value].include?('%')
    else
      operator = '='
    end
    scope = scope.where("#{column} #{operator} ?", params[:value])
  end
  @count = scope.count
  @more_pages = @count > per_page
  scope.limit!(per_page)
  @records = scope.to_a
  @columns = klass.columns

  erb :admin_table
end

post '/monitor/:net_id' do
  content_type 'application/json'

  @user = get_user
  require_user!

  @net_info = NetInfo.new(id: params[:net_id])
  @net = @net_info.net

  @net_info.monitor!(user: @user)

  { ok: true }.to_json
rescue NetInfo::NotFoundError
  status 404
  { error: true }.to_json
end

post '/unmonitor/:net_id' do
  content_type 'application/json'

  @user = get_user
  require_user!

  if @user.monitoring_net && @user.monitoring_net == @user.logging_net
    status 400
    return 'you cannot stop monitoring a net you are logging'
  end

  @net_info = NetInfo.new(id: params[:net_id])
  @net_info.stop_monitoring!(user: @user)

  @net = @net_info.net

  { ok: true }.to_json
rescue NetInfo::NotFoundError
  status 404
  { error: true }.to_json
end

post '/message/:net_id' do
  @user = get_user
  require_user!

  message = params[:message].to_s.strip
    .tr("‘ʼ’", "'")
    .tr("“”", '"')
    .tr("-–—−⁃᠆", "-")
    .gsub("…", "...")

  message_with_silly_encoding = message.encode('ISO-8859-1', invalid: :replace, undef: :replace)

  if message_with_silly_encoding.empty?
    status 400
    return 'no message sent'
  end

  @net_info = NetInfo.new(id: params[:net_id])
  @net = @net_info.net

  content_type 'application/json'

  if @user.monitoring_net != @net
    status 401
    return { error: 'not monitoring this net' }.to_json
  end

  @net_info.send_message!(user: @user, message: message_with_silly_encoding)

  status 201
  { status: 'sent' }.to_json
rescue NetInfo::ServerError => e
  status 500
  { error: e.message }.to_json
end

get '/group/:slug' do
  @user = get_user

  params[:slug] = CGI.unescape(params[:slug])
  @club = Tables::Club.find_by!(name: params[:slug])
  if @club.about_url.nil?
    status 404
    return erb :missing_club
  end

  @page_title = @club.name

  @net_names = (
    @club.nets.order(:name).pluck(:name) +
    @club.closed_nets.order(:name, :started_at).pluck(:name)
  ).sort.uniq(&:downcase)

  erb :club
rescue ActiveRecord::RecordNotFound
  status 404
  erb :missing_club
end

get '/group/:id/nets.json' do
  @user = get_user
  require_user!

  club = Tables::Club.find(params[:id])

  nets = club.closed_nets
             .where('started_at > ?', 60.days.ago)
             .order(:name, :frequency)
             .select(:id, :name, :frequency, :band, :mode, :started_at)
             .to_a
             .uniq { |n| [n.name.downcase, n.frequency] }

  content_type 'application/json'
  nets.to_json
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

post '/admin/remove_closed_net_from_club' do
  @user = get_user
  require_admin!

  closed_net = Tables::ClosedNet.find(params[:id])
  closed_net.update!(club: nil)

  redirect "/closed-net/#{closed_net.id}"
end

get '/admin/clubs.json' do
  @user = get_user
  require_admin!

  content_type 'application/json'
  attachment 'clubs.json'

  {
    clubs: Tables::Club.order(:name).map do |record|
      if record.logo_url.present?
        path = File.join(__dir__, 'public', record.logo_url)
        if File.exist?(path)
          logo = Base64.encode64(File.read(path))
        end
      end
      record.as_json.except('id', 'created_at', 'updated_at').merge(logo:)
    end
  }.to_json
end

patch '/admin/clubs.json' do
  @user = get_user
  require_admin!

  existing = Tables::Club.all.each_with_object({}) { |c, h| h[c.name.downcase] = c }
  orig_count = existing.size
  created = 0
  updated = 0
  data = params[:file]['tempfile'].read
  JSON.parse(data)['clubs'].each do |row|
    raise 'bad' unless row['name'].present?
    if (logo = row.delete('logo'))
      path = File.join(__dir__, 'public', row['logo_url'])
      File.write(path, Base64.decode64(logo))
    end
    if (found = existing.delete(row['name'].downcase))
      found.attributes = row
      updated += 1 if found.changed?
      found.save!
    else
      Tables::Club.create!(row)
      created += 1
    end
  end
  if existing.size > orig_count * 0.5
    status 400
    erb 'deleting more than half!'
  else
    deleted = existing.size
    existing.values.each(&:destroy)
    erb "#{created} created, #{updated} updated, #{deleted} deleted"
  end
end

post '/pusher/auth/:net_id' do
  @user = get_user
  require_user!

  content_type 'application/json'
  Pusher::Client.from_env.authenticate("private-net-#{params[:net_id]}", params[:socket_id]).to_json
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

def require_user!
  return if @user

  redirect '/'
end

def require_admin!
  return if is_admin?

  if request.get?
    redirect '/login'
  else
    halt 401, 'not authorized'
  end
end

def require_net_logger_role!
  return if has_net_logger_role?

  halt 401, 'not authorized'
end

def check_if_already_started_a_net!(user)
  return unless (existing_net = user.logging_net)

  redirect "/net/#{url_escape existing_net.name}"
end

def fix_club_params(params)
  %i[full_name description logo_url about_url].each do |param|
    params[:club][param] = params[:club][param].presence
  end
  %i[override_about_url override_logo_url].each do |param|
    params[:club][param] = params[:club][param] == 'true'
  end
  %i[net_patterns net_list additional_net_patterns].each do |param|
    params[:club][param] = JSON.parse(params[:club][param]) if params[:club][param]
  end
  params[:club][:logo_url] = UpdateClubList.download_logo_url(@club, params[:club][:logo_url])
end
