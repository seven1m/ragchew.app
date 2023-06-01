require_relative './fetcher'
require_relative './tables'

class UpdateClubList
  def call
    clubs.each do |club_name, url|
      begin
        raw = club_info(url)
      rescue SocketError => e
        puts "error: could not get #{url} (#{e.message})"
      else
        config = parse_config(raw)
        variables = config['Variables'].each_with_object({}) do |line, hash|
          name, value = line.split(/\s*=\s*/, 2)
          hash[name] = value
        end
        Tables::Club.find_or_initialize_by(name: club_name).update!(
          profile_url: url,
          about_url: variables['AboutURL'],
          logo_url: variables['LogoURL'],
          logo_updated_at: variables['LogoTimeStamp'],
          expiration_time: variables['ExpirationTime'],
          current_net_expiration_time: variables['CurrentNetExpirationTime'],
          net_patterns: config['Nets'],
          net_list: net_list(config['NetList']),
        )
      end
    end
  end

  private

  def net_list(lines)
    (lines || []).map do |line|
      name, band, frequency, mode, host = line.split(/\s*\|\s*/)
      {
        name:,
        band:,
        frequency:,
        mode:,
        host:,
      }
    end
  end

  def clubs
    hash = {}
    Tables::Server.all.map(&:club_info_list_url).compact.uniq.each do |url|
      text = Net::HTTP.get(URI(url)).force_encoding('ISO-8859-1')
      section = parse_config(text)['ClubInfoList']
      section.grep_v(/^\s*#|^\s*$/).each do |line|
        club, url = line.strip.split(/\s*\|\s*/)
        hash[club] = url
      end
    end
    hash
  end

  def club_info(url)
    Net::HTTP.get(URI(url))
  end

  def parse_config(text)
    sections = {}
    section = nil
    text.split(/\r?\n/).each do |line|
      if line =~ /^\[(.+)\]/
        section = $1
      else
        sections[section] ||= []
        sections[section] << line if line.present? && !line.start_with?('#')
      end
    end
    sections
  end
end
