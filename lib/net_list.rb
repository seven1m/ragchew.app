require 'net/http'
require 'time'

require_relative './fetcher'
require_relative './tables'

class NetList
  CACHE_LENGTH_IN_SECONDS = 30
  SERVER_CACHE_LENGTH_IN_SECONDS = 3600

  def list
    update_cache
    Tables::Net.order(:name)
  end

  private

  def update_cache
    Tables::Server.transaction do
      update_server_cache
    end
    Tables::Net.transaction do
      update_net_cache
    end
  end

  def update_server_cache
    last_updated = Tables::Server.maximum(:updated_at)
    return if last_updated && last_updated > Time.now - SERVER_CACHE_LENGTH_IN_SECONDS

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

      record = cached.delete(host) || Tables::Server.new(host:)
      record.update!(
        name: details['ServerName'],
        state: details['ServerState'],
        is_public:,
        server_created_at: Time.parse(details['CreationDateUTC']),
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

  def update_net_cache
    last_updated = Tables::Net.maximum(:partially_updated_at)
    return if last_updated && last_updated > Time.now - CACHE_LENGTH_IN_SECONDS

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

    # delete existing no longer active
    cached.values.each(&:destroy)

    # update all the timestamps at once
    Tables::Net.update_all(partially_updated_at: Time.now)
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
