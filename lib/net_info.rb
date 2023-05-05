require 'time'

require_relative './fetcher'
require_relative './tables'

class NetInfo
  CACHE_LENGTH_IN_SECONDS = 30

  class NotFoundError < StandardError; end

  def initialize(name)
    @name = name
    @record = Tables::Net.find_by!(name:)
  rescue ActiveRecord::RecordNotFound
    raise NotFoundError, "Net not found"
  end

  def info
    if !@record.fully_updated_at || @record.fully_updated_at < Time.now - CACHE_LENGTH_IN_SECONDS
      update_cache
    end

    @record
  end

  private

  def update_cache
    data = fetch

    update_checkins(data[:checkins])
    update_monitors(data[:monitors])
    update_messages(data[:messages])

    # do this last
    update_net_info(
      data[:info].merge(
        partially_updated_at: Time.now,
        fully_updated_at: Time.now
      )
    )
  end

  def update_net_info(info)
    @record.update!(info.merge(updated_at: Time.now))
  end

  def update_checkins(checkins)
    records = @record.checkins.all
    checkins.each do |checkin|
      if (existing = records.detect { |r| r.num == checkin[:num] })
        existing.update!(checkin)
      else
        @record.checkins.create!(checkin)
      end
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
    begin
      fetcher = Fetcher.new(@record.host)
      # DeltaUpdateTime=2023-05-04%2001:54:25&IMSerial=1192458&LastExtDataSerial=570630
    rescue Fetcher::NotFoundError => e
      raise NotFoundError, e.message
    end

    data = fetcher.get(
      'GetUpdates3.php',
      'ProtocolVersion' => '2.3',
      'NetName' => CGI.escape(@record.name)
    )

    checkins = data['NetLogger Start Data'].map do |num, call_sign, city, state, name, remarks, qsl_info, checked_in_at, county, grid_square, street, zip, status, _unknown, country, dxcc, first_name|
      next if call_sign == 'future use 2'
      {
        num:,
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

    messages = data['IM Start'].map do |log_id, call_sign, _always_one, message, sent_at, ip_address|
      {
        log_id:,
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
      info:
    }
  end
end
