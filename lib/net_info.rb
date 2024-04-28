require 'time'

require_relative './fetcher'
require_relative './tables'
require_relative './user_presenter'

class NetInfo
  EARTH_RADIUS_IN_KM = 6378.137
  CENTER_PERCENTILE = 75
  MIN_LATITUDES_FOR_MAJORITY = 3
  MIN_LONGITUDES_FOR_MAJORITY = 3
  MIN_CENTER_RADIUS_IN_METERS = 50000
  MAX_CENTER_RADIUS_TO_SHOW = 3000000
  LOCK_TIMEOUT = 2

  class NotFoundError < StandardError; end

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

  def net = @record
  def name = @record.name
  def host = @record.host

  def update!
    return unless cache_needs_updating?

    with_lock do
      if cache_needs_updating?
        update_cache
      end
    end
  end

  def update_net_right_now_with_wreckless_disregard_for_the_last_update!
    with_lock do
      update_cache
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

    with_lock do
      message_record = @record.messages.create!(
        log_id: nil, # temporary messages don't have a log_id
        call_sign: name_for_chat(user),
        message:,
        sent_at: Time.now,
      )
      Pusher::Client.from_env.trigger(
        "private-net-#{@record.id}",
        'message',
        message: message_record.as_json
      )
    end

    fetcher = Fetcher.new(@record.host)
    fetcher.post(
      'SendInstantMessage.php',
      'NetName' => @record.name,
      'Callsign' => name_for_chat(user),
      'Message' => message,
    )
  end

  private

  def update_cache
    data = fetch

    changes = update_checkins(data[:checkins], currently_operating: data[:currently_operating])
    changes += update_monitors(data[:monitors])
    changes += update_messages(data[:messages])

    # update this last
    update_net_info(data[:info])

    # let connected clients know
    if changes > 0
      Pusher::Client.from_env.trigger(
        "private-net-#{@record.id}",
        'net-updated',
        changes:,
        updatedAt: @record.updated_at.rfc3339,
      )
    end
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
    records = @record.checkins.to_a

    changes = 0

    checkins.each do |checkin|
      if (existing = records.detect { |r| r.num == checkin[:num] })
        existing.update!(checkin)
        changes += 1 if existing.previous_changes.any?
      else
        records << @record.checkins.create!(checkin)
        changes += 1
      end
      Tables::Station.find_or_initialize_by(call_sign: checkin[:call_sign]).update!(
        last_heard_on: @record.name,
        last_heard_at: checkin[:checked_in_at],
      )
    end

    stored_currently_operating = records.detect { |r| r.currently_operating? }&.num
    if currently_operating && stored_currently_operating != currently_operating
      old_record = records.detect { |r| r.num == stored_currently_operating }
      new_record = records.detect { |r| r.num == currently_operating }
      if old_record
        old_record.update!(currently_operating: false)
        changes += 1
      end
      if new_record
        new_record.update!(currently_operating: true)
        changes += 1
      end
    end

    changes
  end

  def update_monitors(monitors)
    changes = 0

    records = @record.monitors.all
    monitors.each do |monitor|
      if (existing = records.detect { |r| r.call_sign == monitor[:call_sign] })
        existing.update!(monitor)
        changes += 1 if existing.previous_changes.any?
      else
        @record.monitors.create!(monitor)
        changes += 1
      end
    end

    changes
  end

  def update_messages(messages)
    changes = 0

    records = @record.messages.all
    messages.each do |message|
      if (existing = records.detect { |r| r.log_id == message[:log_id] })
        existing.update!(message)
        changes += 1 if existing.previous_changes.any?
      else
        @record.messages.create!(message)
        changes += 1
      end
    end

    temporary_messages_to_cleanup = records.select { |r| r.log_id.nil? }
    temporary_messages_to_cleanup.each(&:destroy)

    changes
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

  def with_lock
    Tables::Net.with_advisory_lock(:update_net_cache, timeout_seconds: LOCK_TIMEOUT) do
      @record.reload
      yield
    end
  end
end
