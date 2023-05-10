require 'time'

require_relative './fetcher'
require_relative './tables'

class NetInfo
  class NotFoundError < StandardError; end

  def initialize(name)
    @name = name
    @record = Tables::Net.find_by!(name:)
  rescue ActiveRecord::RecordNotFound
    raise NotFoundError, "Net is closed"
  end

  def info
    if !@record.fully_updated_at || @record.fully_updated_at < Time.now - @record.update_interval_in_seconds
      update_cache
    end

    @record
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
      {
        num: num.to_i,
        call_sign:,
        city:,
        state:,
        name:,
        remarks:,
        qsl_info:,
        checked_in_at: Time.parse(checked_in_at),
        county:,
        grid_square:,
        street:,
        zip:,
        status:,
        country:,
        nickname:,
      }
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
      {
        log_id: log_id.to_i,
        call_sign:,
        message:,
        sent_at: Time.parse(sent_at),
        ip_address:
      }
    end

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
end
