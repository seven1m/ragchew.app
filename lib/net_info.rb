require 'time'

require_relative './fetcher'
require_relative './tables'

class NetInfo
  NET_LOGGER_FAKE_VERSION = 'v3.1.7L'
  EARTH_RADIUS_IN_KM = 6378.137
  CENTER_PERCENTILE = 75
  MIN_LATITUDES_FOR_MAJORITY = 3
  MIN_LONGITUDES_FOR_MAJORITY = 3
  MIN_CENTER_RADIUS_IN_METERS = 50000
  MAX_CENTER_RADIUS_TO_SHOW = 3000000

  class NotFoundError < StandardError; end
  class CouldNotCreateNetError < StandardError; end
  class CouldNotCloseNetError < StandardError; end

  class UserPresenter
    def initialize(user)
      @user = user
    end

    def name_for_monitoring
      name = name_for_chat
      # NOTE: must use a real version here or UnsubscribeFromNet won't work :-(
      name + " - #{NET_LOGGER_FAKE_VERSION}"
    end

    alias name_for_logging name_for_monitoring

    def name_for_chat
      name = @user.call_sign
      name += '-' + @user.first_name unless @user.first_name.to_s.strip.empty?
      name.upcase
    end
  end

  def initialize(name: nil, id: nil)
    if id
      @record = Tables::Net.find_by!(id:)
    elsif name
      @record = Tables::Net.find_by!(name:)
    else
      raise 'must supply either id or name to NetInfo.new'
    end
  rescue ActiveRecord::RecordNotFound
    raise NotFoundError, 'Net is closed'
  end

  def self.create_net!(name:, password:, frequency:, net_control:, user:, mode:, band:, enable_messaging: true, update_interval: 20000, misc_net_parameters: nil, host: 'www.netlogger.org')
    user = UserPresenter.new(user)
    fetcher = Fetcher.new(host)
    result = fetcher.raw_get(
      'OpenNet20.php',
      'NetName' => name,
      'Token' => password,
      'Frequency' => frequency,
      'NetControl' => net_control,
      'Logger' => user.name_for_logging,
      'Mode' => mode,
      'Band' => band,
      'EnableMessaging' => enable_messaging ? 'Y' : 'N',
      'UpdateInterval' => update_interval.to_s,
      'MiscNetParameters' => misc_net_parameters.to_s,
    )
    unless result =~ /\*success\*/
      raise CouldNotCreateNetError, result
    end
  end

  def net
    @record
  end

  def update!
    return unless cache_needs_updating?

    Tables::Net.with_advisory_lock(:update_net_cache, timeout_seconds: 2) do
      @record.reload
      if cache_needs_updating?
        update_cache
      end
    end
  end

  def monitor!(user:)
    if user.monitoring_net && user.monitoring_net != @record
      # already monitoring one, so stop that first
      begin
        NetInfo.new(id: user.monitoring_net_id).stop_monitoring!(user:)
      rescue NetInfo::NotFoundError
        # no biggie I guess
      end
    end

    # 2023-05-09 17:40:45 GET http://www.netlogger.org/cgi-bin/NetLogger/SubscribeToNet.php?ProtocolVersion=2.3&NetName=Daily%20Check%20in%20Net&Callsign=KI5ZDF-TIM%20MORGAN%20-%20v3.1.7L&IMSerial=0&LastExtDataSerial=0                                                                                                                                                     
    #                        ← 200 OK text/html 2.15k 150ms
    #                             Request                                                          Response                                                          Detail
    #Host:          www.netlogger.org                                                                                                                                                                 
    #Accept:        www/source, text/html, video/mpeg, image/jpeg, image/x-tiff, image/x-rgb, image/x-xbm, image/gif, */*, application/postscript                                                     
    #Content-Type:  application/x-www-form-urlencoded                                                                                                                                                 
    #Query                                                                                                                                                                                      [m:auto]
    #ProtocolVersion:   2.3
    #NetName:           Daily Check in Net
    #Callsign:          KI5ZDF-TIM MORGAN - v3.1.7L
    #IMSerial:          0
    #LastExtDataSerial: 0

    fetcher = Fetcher.new(@record.host)
    fetcher.get(
      'SubscribeToNet.php',
      'ProtocolVersion' => '2.3',
      'NetName' => @record.name,
      'Callsign' => name_for_monitoring(user),
      'IMSerial' => '0',
      'LastExtDataSerial' => '0',
    )
    user.update!(monitoring_net: @record)
  end

  def stop_monitoring!(user:)
    # 2023-05-09 17:41:58 GET http://www.netlogger.org/cgi-bin/NetLogger/UnsubscribeFromNet.php?&Callsign=KI5ZDF-TIM%20MORGAN%20-%20v3.1.7L&NetName=Daily%20Check%20in%20Net                           
    #                        ← 200 OK text/html 176b 143ms
    #                             Request                                                          Response                                                          Detail
    #Host:          www.netlogger.org                                                                                                                                                                 
    #Accept:        www/source, text/html, video/mpeg, image/jpeg, image/x-tiff, image/x-rgb, image/x-xbm, image/gif, */*, application/postscript                                                     
    #Content-Type:  application/x-www-form-urlencoded                                                                                                                                                 
    #Query                                                                                                                                                                                      [m:auto]
    #Callsign: KI5ZDF-TIM MORGAN - v3.1.7L
    #NetName:  Daily Check in Net

    fetcher = Fetcher.new(@record.host)
    begin
      fetcher.get(
        'UnsubscribeFromNet.php',
        'Callsign' => name_for_monitoring(user),
        'NetName' => @record.name,
      )
    rescue Fetcher::NotFoundError => e
      raise NotFoundError, 'Already unsubscribed'
    end
  end

  def send_message!(user:, message:)
    # 2023-05-09 17:24:31 POST http://www.netlogger.org/cgi-bin/NetLogger/SendInstantMessage.php                                                                                                       
    #                         ← 200 OK text/html 176b 206ms
    #                             Request                                                          Response                                                          Detail
    #Host:            www.netlogger.org                                                                                                                                                               
    #Accept:          www/source, text/html, video/mpeg, image/jpeg, image/x-tiff, image/x-rgb, image/x-xbm, image/gif, */*, application/postscript                                                   
    #Content-Type:    application/x-www-form-urlencoded                                                                                                                                               
    #Content-Length:  130                                                                                                                                                                             
    #URLEncoded form                                                                                                                                                                            [m:auto]
    #NetName:      Test net JUST TESTING
    #Callsign:     KI5ZDF-TIM MORGAN
    #IsNetControl: X
    #Message:      hello just testing https://ragchew.app
    fetcher = Fetcher.new(@record.host)
    fetcher.post(
      'SendInstantMessage.php',
      'NetName' => name,
      'Callsign' => name_for_chat(user),
      'Message' => message,
    )
  end

  def log_entry!(password:, mode:, num:, call_sign:, city:, state:, first_name:, last_name:, remarks:, county:, grid_square:, street:, zip:, country:, dxcc:, preferred_name:, official_status: nil)
    # A|1|KI5ZDF|Tulsa|OK|Tim R Morgan|      | |Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States| |Tim~`1|future use 2|future use 3|`^future use 4|future use 5^
    # A|2|KI5ZDG|Tulsa|OK|Kai Morgan  |      | |Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States| |Wesley Kai~`1|future use 2|future use 3|`^future use 4|future use 5^
    # U|1|KI5ZDF|Tulsa|OK|Tim R Morgan|remarks| |Tulsa|EM26aa|10727 Riverside Pkwy|74137|(nc)| |United States| |Tim~`1|future use 2|future use 3|`^future use 4|future use 5^

    raise 'must specify num' unless num.present?

    highlight_num = 1 # TODO

    begin
      info = qrz.lookup(call_sign)
    rescue Qrz::Error
      # well we tried
      info = { call_sign: call_sign.upcase }
    end

    line1 = [
      mode,
      num,
      call_sign,
      city,
      state,
      [first_name, last_name].compact.join(' '),
      remarks,
      '', # unknown
      county,
      grid_square,
      street,
      zip,
      official_status,
      '', # unknown
      country,
      dxcc,
      preferred_name,
    ].map { |cell| cell.to_s.tr('|~`', ' ') }.join('|')
    line2 = "`#{highlight_num}|future use 2|future use 3|`^future use 4|future use 5^"
    data = [line1, line2].join('~')

    fetcher = Fetcher.new(@record.host)
    fetcher.post(
      'SendUpdates3.php',
      'ProtocolVersion' => '2.3',
      'NetName' => @record.name,
      'Token' => password,
      'UpdatesFromNetControl' => data,
    )
  end

  def delete_log_entry!(num:)
    # TODO
  end

  def close_net!(password:)
    fetcher = Fetcher.new(@record.host)
    result = fetcher.raw_get(
      'CloseNet.php',
      'NetName' => @record.name,
      'Token' => password,
    )
    unless result =~ /\*success\*/
      raise CouldNotCloseNetError, result
    end
  end

  private

  def update_cache
    data = fetch

    update_checkins(data[:checkins], currently_operating: data[:currently_operating])
    update_monitors(data[:monitors])
    update_messages(data[:messages])

    # do this last
    update_net_info(data[:info])
  end

  def update_net_info(info)
    update_center
    @record.fully_updated_at = Time.now
    @record.update!(info)
  end

  def update_center
    checkins = @record.checkins.to_a

    minority_factor = (100 - CENTER_PERCENTILE) / 100.0

    latitudes = checkins.map(&:latitude).compact.sort
    minority_lat_size = (latitudes.size * minority_factor).to_i
    if minority_lat_size >= 2
      majority_latitudes = latitudes[(minority_lat_size / 2)...-(minority_lat_size / 2)]
    else
      majority_latitudes = latitudes
    end
    @record.center_latitude = average([majority_latitudes.first, majority_latitudes.last])

    longitudes = checkins.map(&:longitude).compact.sort
    minority_lon_size = (longitudes.size * minority_factor).to_i
    if minority_lon_size >= 2
      majority_longitudes = longitudes[(minority_lon_size / 2)...-(minority_lon_size / 2)]
    else
      majority_longitudes = longitudes
    end
    @record.center_longitude = average([majority_longitudes.first, majority_longitudes.last])

    if majority_latitudes.any? && majority_longitudes.any?
      distance = haversine_distance_in_meters(
        majority_latitudes.first,
        majority_longitudes.first,
        majority_latitudes.last,
        majority_longitudes.last,
      )
      radius = [distance / 2, MIN_CENTER_RADIUS_IN_METERS].max
      @record.center_radius = radius <= MAX_CENTER_RADIUS_TO_SHOW ? radius : nil
    end
  end

  def update_checkins(checkins, currently_operating:)
    records = @record.checkins.all

    checkins.each do |checkin|
      if (existing = records.detect { |r| r.num == checkin[:num] })
        existing.update!(checkin)
      else
        @record.checkins.create!(checkin)
      end
      Tables::Station.find_or_initialize_by(call_sign: checkin[:call_sign]).update!(
        last_heard_on: @record.name,
        last_heard_at: checkin[:checked_in_at],
      )
    end

    if currently_operating && records.detect { |r| r.currently_operating? }&.num != currently_operating
      @record.checkins.update_all("currently_operating = (num = #{currently_operating.to_i})")
    end
  end

  def update_monitors(monitors)
    records = @record.monitors.all
    monitors.each do |monitor|
      if (existing = records.detect { |r| r.call_sign == monitor[:call_sign] })
        existing.update!(monitor)
      else
        @record.monitors.create!(monitor)
      end
    end
  end

  def update_messages(messages)
    records = @record.messages.all
    messages.each do |message|
      if (existing = records.detect { |r| r.log_id == message[:log_id] })
        existing.update!(message)
      else
        @record.messages.create!(message)
      end
    end
  end

  def cache_needs_updating?
    !@record.fully_updated_at || @record.fully_updated_at < Time.now - @record.update_interval_in_seconds
  end

  def fetch
    data = fetch_raw

    checkins = data['NetLogger Start Data'].map do |num, call_sign, city, state, name, remarks, qsl_info, checked_in_at, county, grid_square, street, zip, status, _unknown, country, dxcc, nickname|
      next if call_sign == 'future use 2'
      (latitude, longitude) = GridSquare.new(grid_square).to_a

      begin
        checked_in_at = Time.parse(checked_in_at)
      rescue ArgumentError, TypeError
        # bad checkin?
        nil
      else
        if call_sign.size > 2 && grid_square == ' '
          # The NetLogger operator doesn't have a QRZ account,
          # so we'll look up some info for them using ours.
          begin
            info = qrz.lookup(call_sign)
          rescue Qrz::Error
            # well we tried
          else
            grid_square = info[:grid_square]
            name = [info[:first_name], info[:last_name]].compact.join(' ') unless name.present?
            street = info[:street] unless street.present?
            city = info[:city] unless city.present?
            state = info[:state] unless state.present?
            zip = info[:zip] unless zip.present?
            county = info[:county] unless county.present?
            country = info[:country] unless country.present?
          end
        end

        {
          num: num.to_i,
          call_sign:,
          city:,
          state:,
          name:,
          remarks:,
          qsl_info:,
          checked_in_at:,
          county:,
          grid_square:,
          street:,
          zip:,
          status:,
          country:,
          nickname:,
          latitude:,
          longitude:,
        }
      end
    end.compact

    last_record = data['NetLogger Start Data'].last
    if last_record && last_record[0] =~ /^`(\d+)/
      currently_operating = $1.to_i
    end

    monitors = data['NetMonitors Start'].map do |call_sign_and_info, ip_address|
      parts = call_sign_and_info.split(' - ')
      call_sign, name = parts.first.split('-')
      version = parts.grep(/v\d/).last
      status = parts.grep(/(On|Off)line/).first || 'Online'
      {
        call_sign:,
        name:,
        version:,
        status:,
        ip_address:,
      }
    end

    messages = data['IM Start'].map do |log_id, call_sign, _always_one, message, sent_at, ip_address|
      begin
        sent_at = Time.parse(sent_at)
      rescue ArgumentError, TypeError
        # bad message?
        nil
      else
        {
          log_id: log_id.to_i,
          call_sign:,
          message:,
          sent_at:,
          ip_address:
        }
      end
    end.compact

    raw_info = (data['Net Info Start'].first || []).each_with_object({}) do |param, hash|
      (key, value) = param.split('=')
      hash[key.downcase] = value
    end
    info = {
      started_at: raw_info['date'],
      frequency: raw_info['frequency'],
      net_logger: raw_info['logger'],
      net_control: raw_info['netcontrol'],
      mode: raw_info['mode'],
      band: raw_info['band'],
      im_enabled: raw_info['aim'] == 'Y',
      update_interval: raw_info['updateinterval'],
      alt_name: raw_info['altnetname'],
    }

    {
      checkins:,
      monitors:,
      messages:,
      info:,
      currently_operating:
    }
  end

  def fetch_raw(force_full: false)
    unless force_full
      log_last_updated_at = @record.checkins.maximum(:checked_in_at)
      im_last_serial = @record.messages.maximum(:log_id)
    end

    fetcher = Fetcher.new(@record.host)
    # LastExtDataSerial=570630

    params = {
      'ProtocolVersion' => '2.3',
      'NetName' => @record.name
    }

    if (log_last_updated_at)
      params.merge!(
        'DeltaUpdateTime' => log_last_updated_at.strftime('%Y-%m-%d %H:%M:%S')
      )
    end

    if (im_last_serial)
      params.merge!(
        'IMSerial' => im_last_serial
      )
    end

    begin
      fetcher.get('GetUpdates3.php', params)
    rescue Fetcher::NotFoundError => e
      Tables::ClosedNet.from_net(@record).save!
      @record.destroy
      raise NotFoundError, 'Net is closed'
    end
  end

  def name_for_monitoring(user)
    UserPresenter.new(user).name_for_monitoring
  end

  def name_for_chat(user)
    UserPresenter.new(user).name_for_chat
  end

  def median(ary)
    return if ary.empty?

    if ary.size.odd?
      ary[ary.size / 2]
    else
      (ary[(ary.size - 1) / 2] + ary[ary.size / 2]) / 2.0
    end
  end

  def average(ary)
    ary = ary.compact
    return if ary.empty?

    ary.sum / ary.size.to_f
  end

  # https://stackoverflow.com/a/11172685
  def haversine_distance_in_meters(lat1, lon1, lat2, lon2)
    dLat = lat2 * Math::PI / 180 - lat1 * Math::PI / 180
    dLon = lon2 * Math::PI / 180 - lon1 * Math::PI / 180
    a = Math.sin(dLat/2) * Math.sin(dLat/2) +
        Math.cos(lat1 * Math::PI / 180) *
        Math.cos(lat2 * Math::PI / 180) *
        Math.sin(dLon/2) * Math.sin(dLon/2)
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    d = EARTH_RADIUS_IN_KM * c
    d * 1000
  end

  def qrz
    @qrz ||= QrzAutoSession.new
  end
end
