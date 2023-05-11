require 'time'

require_relative './fetcher'
require_relative './tables'

class NetInfo
  NET_LOGGER_FAKE_VERSION = 'v3.1.7L'

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
    raise NotFoundError, "Net is closed"
  end

  def net
    if !@record.fully_updated_at || @record.fully_updated_at < Time.now - @record.update_interval_in_seconds
      update_cache
    end

    @record
  end

  def net_without_cache_update
    @record
  end

  def monitor!(user:)
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
      'NetName' => CGI.escapeURIComponent(@record.name),
      'Callsign' => CGI.escapeURIComponent(name_for_monitoring(user)),
      'IMSerial' => '0',
      'LastExtDataSerial' => '0',
    )
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
    fetcher.get(
      'UnsubscribeFromNet.php',
      'Callsign' => CGI.escapeURIComponent(name_for_monitoring(user)),
      'NetName' => CGI.escapeURIComponent(@record.name),
    )
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
      'NetName' => @record.name,
      'Callsign' => name_for_chat(user),
      'Message' => message,
    )
  end

  private

  def update_cache
    Tables::Net.transaction do
      data = fetch

      update_checkins(data[:checkins], currently_operating: data[:currently_operating])
      update_monitors(data[:monitors])
      update_messages(data[:messages])

      # do this last
      update_net_info(data[:info])
    end
  end

  def update_net_info(info)
    @record.fully_updated_at = Time.now
    @record.update!(info)
  end

  def update_checkins(checkins, currently_operating:)
    records = @record.checkins.all
    checkins.each do |checkin|
      if (existing = records.detect { |r| r.num == checkin[:num] })
        existing.update!(checkin)
      else
        @record.checkins.create!(checkin)
      end
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

  def fetch
    log_last_updated_at = @record.checkins.maximum(:checked_in_at)
    im_last_serial = @record.messages.maximum(:log_id)

    fetcher = Fetcher.new(@record.host)
    # LastExtDataSerial=570630

    params = {
      'ProtocolVersion' => '2.3',
      'NetName' => CGI.escape(@record.name)
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
      data = fetcher.get('GetUpdates3.php', params)
    rescue Fetcher::NotFoundError => e
      raise NotFoundError, "Net is closed (#{e.message})"
    end

    checkins = data['NetLogger Start Data'].map do |num, call_sign, city, state, name, remarks, qsl_info, checked_in_at, county, grid_square, street, zip, status, _unknown, country, dxcc, nickname|
      next if call_sign == 'future use 2'
      begin
        checked_in_at = Time.parse(checked_in_at)
      rescue ArgumentError
        # bad checkin?
        nil
      else
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
        }
      end
    end.compact

    if data['NetLogger Start Data'].last[0] =~ /^`(\d+)/
      currently_operating = $1.to_i
    end

    monitors = data['NetMonitors Start'].map do |call_sign_and_info, ip_address|
      call_sign, version, status = call_sign_and_info.split(' - ')
      {
        call_sign:,
        version:,
        status: status || 'Online',
        ip_address:,
      }
    end

    messages = data['IM Start'].map do |log_id, call_sign, _always_one, message, sent_at, ip_address|
      begin
        sent_at = Time.parse(sent_at)
      rescue ArgumentError
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

    raw_info = data['Net Info Start'].first.each_with_object({}) do |param, hash|
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

  def name_for_monitoring(user)
    name = name_for_chat(user)
    # NOTE: must use a real version here or UnsubscribeFromNet won't work :-(
    name + " - #{NET_LOGGER_FAKE_VERSION}"
  end

  def name_for_chat(user)
    name = user.call_sign
    name += '-' + user.first_name unless user.first_name.to_s.strip.empty?
    name.upcase
  end
end
