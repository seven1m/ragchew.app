require 'time'

require_relative './fetcher'
require_relative './tables'

class NetList
  NET_LOGGER_HOSTS = %w[netlogger.org netlogger2.org netlogger3.org netlogger4.org]
  CACHE_LENGTH_IN_SECONDS = 30

  def list
    last_updated = Tables::Net.maximum(:partially_updated_at)
    if !last_updated || last_updated < Time.now - CACHE_LENGTH_IN_SECONDS
      update_cache
    end

    Tables::Net.order(:name)
  end

  private

  def update_cache
    data = fetch
    cached = Tables::Net.all_by_name

    # update existing and create new
    data.each do |net_info|
      net_info.merge!(partially_updated_at: Time.now)
      if (net = cached[net_info[:name]])
        net.update!(net_info)
        cached.delete(net.name)
      else
        Tables::Net.create!(net_info)
      end
    end

    # delete existing no longer active
    cached.values.each(&:destroy)
  end

  def fetch
    NET_LOGGER_HOSTS.flat_map do |host|
      fetcher = Fetcher.new(host)
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
          host:,
        }
      end
    end
  end
end
