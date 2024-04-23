require 'time'

require_relative './fetcher'
require_relative './tables'
require_relative './user_presenter'

class NetLogger
  class CouldNotCreateNetError < StandardError; end
  class CouldNotCloseNetError < StandardError; end

  def initialize(net_info, password:)
    @net_info = net_info
    @password = password
    @fetcher = Fetcher.new(@net_info.host)
  end

  attr_reader :net_info, :password, :fetcher

  def append!(entry)
    send_update!([entry.merge(mode: 'A', num: next_num)])
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def insert!(num, entry)
    entries = net_info.net.checkins.where('num >= ?', num).order(:num).map do |entry|
      entry.attributes.symbolize_keys.merge(
        mode: 'U',
        num: entry.num + 1,
      )
    end
    entries.last[:mode] = 'A'
    entries.unshift(entry.merge(mode: 'U', num: num))
    send_update!(entries)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def update!(num, entry)
    entries = [entry.merge(mode: 'U', num:)]
    send_update!(entries)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def delete!(num)
    entries = net_info.net.checkins.where('num > ?', num).order(:num).map do |entry|
      entry.attributes.symbolize_keys.merge(
        mode: 'U',
        num: entry.num - 1,
      )
    end
    blank_attributes = Tables::Checkin.new.attributes
    entries << blank_attributes.symbolize_keys.merge(
      num:,
      mode: 'U',
      call_sign: '',
    )
    send_update!(entries)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def next_num
    @net_info.net.checkins.maximum(:num).to_i + 1
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
    NetList.new.update_net_list_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def close_net!
    fetcher = Fetcher.new(net_info.host)
    result = fetcher.raw_get(
      'CloseNet.php',
      'NetName' => net_info.name,
      'Token' => password,
    )
    unless result =~ /\*success\*/
      raise CouldNotCloseNetError, result
    end
    NetList.new.update_net_list_right_now_with_wreckless_disregard_for_the_last_update!
  end

  private

  def send_update!(entries)
    lines = entries.map do |entry|
      mode = entry.fetch(:mode)
      raise 'mode must be A or U' unless %w[A U].include?(mode)

      [
        mode,
        entry.fetch(:num),
        entry.fetch(:call_sign).upcase,
        entry[:city],
        entry[:state],
        [entry[:first_name], entry[:last_name]].compact.join(' '),
        entry[:remarks],
        '', # unknown
        entry[:county],
        entry[:grid_square],
        entry[:street],
        entry[:zip],
        entry[:official_status],
        '', # unknown
        entry[:country],
        entry[:dxcc],
        entry[:preferred_name],
      ].map { |cell| cell.present? ? cell.to_s.tr('|~`', ' ') : ' ' }.join('|')
    end

    highlight_num = 1 # TODO
    lines << "`#{highlight_num}|future use 2|future use 3|`^future use 4|future use 5^"
    data = lines.join('~')

    fetcher = Fetcher.new(net_info.host)
    fetcher.post(
      'SendUpdates3.php',
      'ProtocolVersion' => '2.3',
      'NetName' => net_info.name,
      'Token' => password,
      'UpdatesFromNetControl' => data,
    )
  end
end
