require 'net/http'
require 'time'

require_relative './fetcher'
require_relative './tables'

class NetList
  CACHE_LENGTH_IN_SECONDS = 30
  SERVER_CACHE_LENGTH_IN_SECONDS = 3600

  def list
    update_cache
    Tables::Net.order(:name).to_a
  end

  private

  def update_cache
    if server_cache_needs_updating?
      Tables::Net.with_advisory_lock(:update_server_list_cache, timeout_seconds: 2) do
        if server_cache_needs_updating?
          update_server_cache
        end
      end
    end

    if net_cache_needs_updating?
      Tables::Net.with_advisory_lock(:update_net_list_cache, timeout_seconds: 2) do
        if net_cache_needs_updating?
          update_net_cache
        end
      end
    end
  end

  def update_server_cache
    return unless server_cache_needs_updating?

    puts 'Updating server cache'

    text = Net::HTTP.get(URI('http://www.netlogger.org/downloads/ServerList.txt'))

    sections = text.scan(/\[(\w+)\]([^\[\]]*)/m).each_with_object({}) do |(header, data), hash|
      hash[header] = data.strip.split(/\r?\n/)
    end

    cached = Tables::Server.public_by_host

    # add new and update existing
    sections['ServerList'].each do |line|
      host = line.split(/\s*\|\s*/).first

      info = Fetcher.new(host).get('GetServerInfo.pl')
      details = info['Server Info Start'].first.each_with_object({}) do |line, hash|
        key, value = line.split('=')
        hash[key] = value
      end

      is_public = details['ServerState'] == 'Public'

      begin
        server_created_at = Time.parse(details['CreationDateUTC'])
      rescue ArgumentError
        server_created_at = nil
      end

      record = cached.delete(host) || Tables::Server.new(host:)
      record.update!(
        name: details['ServerName'],
        state: details['ServerState'],
        is_public:,
        server_created_at:,
        min_aim_interval: details['MinAIMInterval'],
        default_aim_interval: details['DefaultAIMInterval'],
        token_support: details['TokenSupport'].downcase == 'true',
        delta_updates: details['DeltaUpdates'].downcase == 'true',
        ext_data: details['ExtData'].downcase == 'true',
        timestamp_utc_offset: details['NetLoggerTimeStampUTCOffset'],
        updated_at: Time.now,
      )
    end

    # delete old
    cached.values.each(&:destroy)
  end

  def server_cache_needs_updating?
    last_updated = Tables::Server.maximum(:updated_at)
    !last_updated || last_updated < Time.now - SERVER_CACHE_LENGTH_IN_SECONDS
  end

  def update_net_cache
    return unless net_cache_needs_updating?

    data = fetch
    cached = Tables::Net.all_by_name

    # update existing and create new
    data.each do |net_info|
      if (net = cached.delete(net_info[:name]))
        net.update!(net_info)
      else
        Tables::Net.create!(net_info)
      end
    end

    # archive closed nets
    cached.values.each do |net|
      closed_net = Tables::ClosedNet.new(
        net.attributes.slice(
          'name',
          'frequency',
          'mode',
          'net_control',
          'net_logger',
          'band',
          'started_at',
          'subscribers',
          'host',
          'center_latitude',
          'center_longitude',
          'center_radius',
        )
      )
      closed_net.ended_at = Time.now
      closed_net.checkin_count = net.checkins.count
      closed_net.message_count = net.messages.count
      closed_net.monitor_count = net.monitors.count
      closed_net.save!
      net.destroy
    end

    # update all the timestamps at once
    now = Time.now
    Tables::Net.update_all(partially_updated_at: now)
    Tables::Server.update_all(net_list_fetched_at: now)
  end

  def net_cache_needs_updating?
    last_updated = Tables::Server.maximum(:net_list_fetched_at)
    !last_updated || last_updated < Time.now - CACHE_LENGTH_IN_SECONDS
  end

  def fetch
    Tables::Server.is_public.flat_map do |server|
      fetcher = Fetcher.new(server.host)
      data = fetcher.get('GetNetsInProgress20.php', 'ProtocolVersion' => '2.3')['NetLogger Start Data']
      data.map do |name, frequency, net_logger, net_control, started_at, mode, band, im_enabled, update_interval, alt_name, _blank, subscribers|
        {
          name:,
          alt_name:,
          frequency:,
          mode:,
          net_control:,
          net_logger:,
          band:,
          started_at:,
          im_enabled:,
          update_interval:,
          subscribers:,
          server:,
          host: server.host,
        }
      end
    end
  end
end
