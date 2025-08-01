require 'time'

require_relative './fetcher'
require_relative './tables'
require_relative './user_presenter'

class NetLogger
  class CouldNotCreateNetError < StandardError; end
  class CouldNotFindNetAfterCreationError < StandardError; end
  class CouldNotCloseNetError < StandardError; end
  class PasswordIncorrectError < StandardError; end
  class NotAuthorizedError < StandardError; end

  def initialize(net_info, user:)
    @net_info = net_info
    unless user && user.logging_net == @net_info.net
      raise NotAuthorizedError, 'You are not authorized to access this net.'
    end
    @password = user.logging_password
    @fetcher = Fetcher.new(@net_info.host)
  end

  attr_reader :net_info, :password, :fetcher

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
    checkin = @net_info.net.checkins.find_by(num:)
    checkin.update!(notes: entry[:notes]) if entry[:call_sign] == checkin&.call_sign
    @net_info.update_station_details!(entry[:call_sign], preferred_name: entry[:preferred_name], notes: entry[:notes])
  end

  def update!(num, entry)
    existing = net_info.net.checkins.where('num >= ?', num).count > 0
    mode = existing ? 'U' : 'A'
    entries = [entry.merge(mode:, num:)]
    send_update!(entries)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
    checkin = @net_info.net.checkins.find_by(num:)
    checkin.update!(notes: entry[:notes]) if entry[:call_sign] == checkin&.call_sign
    if entry[:call_sign].present?
      @net_info.update_station_details!(entry[:call_sign], preferred_name: entry[:preferred_name], notes: entry[:notes])
    end
  end

  def delete!(num)
    entries = net_info.net.checkins.where('num > ?', num).order(:num).map do |entry|
      entry.attributes.symbolize_keys.merge(
        mode: 'U',
        num: entry.num - 1,
      )
    end
    blank_attributes = Tables::Checkin.new.attributes
    highest_num = net_info.net.checkins.maximum(:num)
    entries << blank_attributes.symbolize_keys.merge(
      num: highest_num,
      mode: 'U',
      call_sign: '',
    )
    send_update!(entries)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def highlight!(num)
    send_update!([], highlight_num: num)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def next_num
    @net_info.net.checkins.not_blank.maximum(:num).to_i + 1
  end

  def self.create_net!(club:, name:, password:, frequency:, net_control:, user:, mode:, band:, enable_messaging: true, update_interval: 20000, misc_net_parameters: nil, host: 'www.netlogger.org')
    fetcher = Fetcher.new(host)
    result = fetcher.raw_get(
      'OpenNet20.php',
      'NetName' => name,
      'Token' => password,
      'Frequency' => frequency,
      'NetControl' => net_control,
      'Logger' => UserPresenter.new(user).name_for_logging,
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

    net = Tables::Net.where(name:).order(:created_at).last
    raise CouldNotFindNetAfterCreationError, result unless net

    net.update!(club:, created_by_ragchew: true)
    user.update!(logging_net: net, logging_password: password)
  end

  def self.start_logging(net_info, password:, user:)
    fetcher = Fetcher.new(net_info.host)
    result = fetcher.raw_get(
      'CheckToken.php',
      'NetName' => net_info.name,
      'Token' => password,
    )
    unless result =~ /\*success\*/
      raise PasswordIncorrectError, result
    end
    user.update!(logging_net: net_info.net, logging_password: password)
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

  def current_highlight_num
    @net_info.net.checkins.find_by(currently_operating: true)&.num || 0
  end

  private

  def send_update!(entries, highlight_num: current_highlight_num)
    lines = entries.map do |entry|
      mode = entry.fetch(:mode)
      raise 'mode must be A or U' unless %w[A U].include?(mode)

      name = entry.fetch(:name).presence ||
             [entry[:first_name], entry[:last_name]].compact.join(' ')

      [
        mode,
        entry.fetch(:num),
        entry[:call_sign].to_s,
        entry[:city],
        entry[:state],
        name,
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
