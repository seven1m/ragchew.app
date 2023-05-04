require 'bundler/setup'
require 'cgi'
require 'erb'
require 'net/http'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'time'
require 'uri'

ENV['TZ'] = 'UTC'

get '/' do
  @nets = net_list
  erb :index
end

get '/net/:name' do
  @net = net_updates(CGI.unescape(params[:name]))
  erb :net
end

def http_get(endpoint, params)
  params_string = params.map { |k, v| "#{k}=#{v}" }.join('&')
  html = Net::HTTP.get(URI("http://netlogger.org/cgi-bin/NetLogger/#{endpoint}?#{params_string}"))
  {}.tap do |result|
    html.scan(/<\!--(.*?)-->(.*?)<\!--.*?-->/m).each do |section, data|
      result[section.strip] = data.split(/~|\n/).map { |line| line.split('|') }
    end
  end
end

def net_list
  data = http_get('GetNetsInProgress20.php', 'ProtocolVersion' => '2.3')['NetLogger Start Data']
  data.map do |name, frequency, logger, net_control, start_time, mode, band, im_enabled, update_interval, alt_name, _blank, subscribers|
    {
      name:,
      alt_name:,
      frequency:,
      mode:,
      net_control:,
      logger:,
      band:,
      start_time:,
      im_enabled:,
      update_interval:,
      subscribers:,
    }
  end
end

def net_updates(name)
  # DeltaUpdateTime=2023-05-04%2001:54:25&IMSerial=1192458&LastExtDataSerial=570630
  data = http_get('GetUpdates3.php', 'ProtocolVersion' => '2.3', 'NetName' => CGI.escape(name))

  log = data['NetLogger Start Data'].map do |num, call_sign, city, state, name, remarks, qsl_info, checkin_time, county, grid_square, street, zip, status, _unknown, country, dxcc, first_name|
    next if call_sign == 'future use 2'
    {
      num:,
      call_sign:,
      city:,
      state:,
      name:,
      remarks:,
      qsl_info:,
      checkin_time: Time.parse(checkin_time),
      county:,
      grid_square:,
      street:,
      zip:,
      status:,
      _unknown:,
      country:,
      dxcc:,
      first_name:,
    }
  end.compact

  monitors = data['NetMonitors Start'].map do |call_sign_and_info, ip_address|
    call_sign, version, status = call_sign_and_info.split(' - ')
    {
      call_sign:,
      version:,
      status: status || 'Online',
      ip_address:,
    }
  end

  messages = data['IM Start'].map do |id, call_sign, _always_one, message, timestamp, ip_address|
    {
      id:,
      call_sign:,
      message:,
      timestamp: Time.parse(timestamp),
      ip_address:
    }
  end

  info = Hash[data['Net Info Start'].first.map { |param| param.split('=') }]

  {
    log:,
    monitors:,
    messages:,
    info:
  }
end

net = net_list.first

pp net_updates(net[:name])
